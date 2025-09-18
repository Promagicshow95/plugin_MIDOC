/**
 * Name: ModeleReseauBusAvecJSON_Vehicules
 * Author: Combined - Network + JSON + Vehicle Simulation
 * Description: Chargement réseau bus + traitement JSON + simulation véhicules
 */

model ModeleReseauBusAvecJSON_Vehicules

global {
    // CONFIGURATION FICHIERS
    string results_folder <- "../../results/";
    string stops_folder <- "../../results/stopReseau/";
    
    file data_file <- shape_file("../../includes/shapeFileHanoishp.shp");
    geometry shape <- envelope(data_file);
    
    // VARIABLES RÉSEAU
    int total_bus_routes <- 0;
    int total_bus_stops <- 0;
    int matched_stops <- 0;
    int unmatched_stops <- 0;
    bool debug_mode <- false;
    
    // VARIABLES TEMPORELLES (adaptées du modèle Toulouse)
    date starting_date <- date("2024-01-01T08:00:00");
    float step <- 5 #s;
    int simulation_start_time;
    int current_seconds_mod <- 0;
    int time_24h -> int(current_date - date([1970,1,1,0,0,0])) mod 86400;
    
    // STRUCTURES RÉSEAU
    map<string, bus_stop> stopId_to_agent;
    map<string, bus_route> osmId_to_route;
    
    // STRUCTURES POUR NAVIGATION (adaptées du modèle Toulouse)
    map<string, graph> route_graphs;  // osm_id -> graph
    map<string, geometry> route_polylines;  // osm_id -> geometry  
    map<string, list<float>> route_cumulative_distances;  // osm_id -> distances
    
    // VARIABLES JSON
    map<string, list<pair<string, int>>> trip_to_sequence;
    int total_stops_processed <- 0;
    int total_trips_processed <- 0;
    map<string, int> collision_check;
    map<string, string> trip_to_route;

    init {
        write "=== MODÈLE COMBINÉ RÉSEAU + JSON + VÉHICULES ===";
        
        // Calcul heure de démarrage simulation
        simulation_start_time <- (starting_date.hour * 3600) + (starting_date.minute * 60) + starting_date.second;
        write "⏰ Simulation démarre à: " + (simulation_start_time / 3600) + "h" + ((simulation_start_time mod 3600) / 60) + "m";
        
        // 1. CHARGEMENT RÉSEAU
        do load_bus_network;
        do load_gtfs_stops;
        do build_basic_mappings;
        
        // 2. PRÉ-CALCULS POUR NAVIGATION
        do prepare_navigation_structures;
        
        // 3. TRAITEMENT JSON
        do process_json_trips;
        do compute_trip_to_route_mappings;
        do verify_data_structures;
        
        write "\n🎯 INITIALISATION TERMINÉE";
        write "  • Routes: " + total_bus_routes;
        write "  • Arrêts: " + total_bus_stops + " (matchés: " + matched_stops + ")";
        write "  • Trips: " + length(trip_to_sequence.keys);
        write "  • Trips avec routes: " + length(trip_to_route.keys);
    }
    
    // MISE À JOUR TEMPS CHAQUE CYCLE
    reflex update_time_every_cycle {
        current_seconds_mod <- time_24h;
    }
    
    // ==================== SECTION RÉSEAU ====================
    
    action load_bus_network {
        write "\n1. CHARGEMENT RÉSEAU BUS";
        
        int bus_routes_count <- 0;
        int i <- 0;
        bool continue_loading <- true;
        
        loop while: continue_loading and i < 30 {
            string filename <- results_folder + "bus_routes_part" + i + ".shp";
            
            try {
                file shape_file_bus <- shape_file(filename);
                
                create bus_route from: shape_file_bus with: [
                    route_name::string(read("name")),
                    osm_id::string(read("osm_id")),
                    route_type::string(read("route_type")),
                    highway_type::string(read("highway")),
                    length_meters::float(read("length_m"))
                ];
                
                bus_routes_count <- bus_routes_count + length(shape_file_bus);
                i <- i + 1;
                
            } catch {
                if i = 0 {
                    write "⚠️ Aucun fichier de routes trouvé";
                }
                continue_loading <- false;
            }
        }
        
        total_bus_routes <- bus_routes_count;
        write "Routes chargées : " + bus_routes_count;
        
        ask bus_route where (each.shape = nil) { do die; }
        total_bus_routes <- length(bus_route);
        write "Routes avec géométrie valide : " + total_bus_routes;
    }
    
    action load_gtfs_stops {
        write "\n2. CHARGEMENT ARRÊTS GTFS";
        
        string stops_filename <- stops_folder + "gtfs_stops_complete.shp";
        
        try {
            file shape_file_stops <- shape_file(stops_filename);
            
            create bus_stop from: shape_file_stops with: [
                stopId::string(read("stopId")),
                stop_name::string(read("name")),
                closest_route_id::string(read("closest_id")),
                closest_route_dist::float(read("distance")),
                is_matched_str::string(read("matched"))
            ];
            
            total_bus_stops <- length(shape_file_stops);
            
            ask bus_stop {
                is_matched <- (is_matched_str = "TRUE");
                
                if stopId = nil or stopId = "" {
                    stopId <- "stop_" + string(int(self));
                }
                if stop_name = nil or stop_name = "" {
                    stop_name <- "Stop_" + string(int(self));
                }
                
                if is_matched {
                    matched_stops <- matched_stops + 1;
                } else {
                    unmatched_stops <- unmatched_stops + 1;
                }
            }
            
            write "Arrêts chargés : " + total_bus_stops;
            write "  - Matchés avec routes OSM : " + matched_stops;
            write "  - Non matchés : " + unmatched_stops;
            
        } catch {
            write "⚠️ ERREUR : Impossible de charger " + stops_filename;
            total_bus_stops <- 0;
        }
    }
    
    action build_basic_mappings {
        write "\n3. CONSTRUCTION MAPPINGS";
        
        stopId_to_agent <- map<string, bus_stop>([]);
        ask bus_stop {
            if stopId != nil and stopId != "" {
                stopId_to_agent[stopId] <- self;
            }
        }
        
        osmId_to_route <- map<string, bus_route>([]);
        ask bus_route {
            if osm_id != nil and osm_id != "" {
                osmId_to_route[osm_id] <- self;
            }
        }
        
        write "Mappings créés :";
        write "  - stopId -> agent : " + length(stopId_to_agent);
        write "  - osmId -> route : " + length(osmId_to_route);
    }
    
    // ==================== PRÉPARATION NAVIGATION ====================
    
    action prepare_navigation_structures {
        write "\n4. PRÉPARATION STRUCTURES NAVIGATION";
        
        route_graphs <- map<string, graph>([]);
        route_polylines <- map<string, geometry>([]);
        route_cumulative_distances <- map<string, list<float>>([]);
        
        int processed <- 0;
        ask bus_route {
            if osm_id != nil and osm_id != "" and shape != nil {
                route_graphs[osm_id] <- as_edge_graph(self);
                route_polylines[osm_id] <- shape;
                
                // Calcul distances cumulées inline
                list<point> points <- shape.points;
                list<float> cumul_distances <- [0.0];
                float total_length <- 0.0;
                
                loop i from: 1 to: length(points) - 1 {
                    float segment_dist <- points[i-1] distance_to points[i];
                    total_length <- total_length + segment_dist;
                    cumul_distances <- cumul_distances + [total_length];
                }
                
                route_cumulative_distances[osm_id] <- cumul_distances;
                processed <- processed + 1;
            }
        }
        
        write "Structures navigation créées pour " + processed + " routes";
    }
    

    
    // ==================== SECTION JSON ====================
    
    action process_json_trips {
        write "\n5. TRAITEMENT DONNÉES JSON";
        
        string json_filename <- stops_folder + "departure_stops_info_stopid.json";
        trip_to_sequence <- map<string, list<pair<string, int>>>([]);
        trip_to_route <- map<string, string>([]);
        collision_check <- map<string, int>([]);
        
        try {
            file json_f <- text_file(json_filename);
            string content <- string(json_f);
            map<string, unknown> json_data <- from_json(content);
            
            if !(json_data contains_key "departure_stops_info") {
                write "❌ ERREUR: Clé 'departure_stops_info' manquante";
                return;
            }
            
            list<map<string, unknown>> stops_list <- list<map<string, unknown>>(json_data["departure_stops_info"]);
            
            loop stop_index from: 0 to: length(stops_list)-1 {
                map<string, unknown> stop_data <- stops_list[stop_index];
                
                if !(stop_data contains_key "departureStopsInfo") { continue; }
                
                map<string,unknown> subMap <- stop_data["departureStopsInfo"];
                total_stops_processed <- total_stops_processed + 1;
                
                if length(subMap.keys) = 0 { continue; }
                
                loop trip_id over: subMap.keys {
                    if collision_check contains_key trip_id {
                        collision_check[trip_id] <- collision_check[trip_id] + 1;
                    } else {
                        collision_check[trip_id] <- 1;
                    }
                    
                    if !(trip_to_sequence contains_key trip_id) {
                        do parse_trip_sequence(trip_id, subMap[trip_id]);
                    }
                }
            }
            
        } catch {
            write "❌ ERREUR: Impossible de lire le fichier JSON";
        }
    }
    
    action parse_trip_sequence(string trip_id, unknown raw_data) {
        list<list<string>> sequence <- list<list<string>>(raw_data);
        if length(sequence) = 0 { return; }
        
        list<pair<string, int>> sequence_parsed <- [];
        
        loop stop_time_pair over: sequence {
            if length(stop_time_pair) >= 2 {
                string stop_id <- stop_time_pair[0];
                int time_value <- int(stop_time_pair[1]);
                add pair(stop_id, time_value) to: sequence_parsed;
            }
        }
        
        if length(sequence_parsed) > 0 {
            trip_to_sequence[trip_id] <- sequence_parsed;
            total_trips_processed <- total_trips_processed + 1;
        }
    }
    
    action compute_trip_to_route_mappings {
        write "\n6. CALCUL ROUTES DOMINANTES DES TRIPS";
        
        loop trip_id over: trip_to_sequence.keys {
            string dominant_route <- compute_dominant_route_for_trip(trip_id);
            if dominant_route != nil and dominant_route != "" {
                trip_to_route[trip_id] <- dominant_route;
            }
        }
        
        write "→ Trips avec routes: " + length(trip_to_route.keys) + "/" + length(trip_to_sequence.keys);
    }
    
    string compute_dominant_route_for_trip(string trip_id) {
        list<pair<string, int>> sequence <- get_trip_sequence(trip_id);
        if length(sequence) = 0 { return nil; }
        
        map<string, int> route_frequency <- map<string, int>([]);
        
        loop stop_time over: sequence {
            bus_stop stop_agent <- get_stop_for_trip(stop_time.key);
            if stop_agent != nil and stop_agent.closest_route_id != nil and stop_agent.closest_route_id != "" {
                string route_id <- stop_agent.closest_route_id;
                if route_frequency contains_key route_id {
                    route_frequency[route_id] <- route_frequency[route_id] + 1;
                } else {
                    route_frequency[route_id] <- 1;
                }
            }
        }
        
        if length(route_frequency.keys) = 0 { return nil; }
        
        string dominant_route <- "";
        int max_frequency <- 0;
        
        loop route_id over: route_frequency.keys {
            int frequency <- route_frequency[route_id];
            if frequency > max_frequency {
                max_frequency <- frequency;
                dominant_route <- route_id;
            }
        }
        
        return dominant_route;
    }
    
    action verify_data_structures {
        write "\n=== VÉRIFICATION STRUCTURES ===";
        write "→ Trips: " + length(trip_to_sequence.keys);
        write "→ Routes assignées: " + length(trip_to_route.keys);
        write "→ Graphes navigation: " + length(route_graphs.keys);
        write "=====================================";
    }
    
    // ==================== APIS D'ACCÈS ====================
    
    bus_stop get_stop_for_trip(string stop_id) {
        if stopId_to_agent contains_key stop_id {
            return stopId_to_agent[stop_id];
        }
        return nil;
    }
    
    list<pair<string, int>> get_trip_sequence(string trip_id) {
        if trip_to_sequence contains_key trip_id {
            return trip_to_sequence[trip_id];
        }
        return [];
    }
    
    list<pair<bus_stop, int>> get_trip_stops_sequence(string trip_id) {
        list<pair<bus_stop, int>> result <- [];
        list<pair<string, int>> raw_sequence <- trip_to_sequence[trip_id];
        
        loop stop_time over: raw_sequence {
            bus_stop stop_agent <- get_stop_for_trip(stop_time.key);
            if stop_agent != nil {
                add pair(stop_agent, stop_time.value) to: result;
            }
        }
        return result;
    }
    
    string get_trip_dominant_route(string trip_id) {
        if trip_to_route contains_key trip_id {
            return trip_to_route[trip_id];
        }
        return nil;
    }
    
    bus_route get_route_by_osm_id(string osm_id) {
        if osmId_to_route contains_key osm_id {
            return osmId_to_route[osm_id];
        }
        return nil;
    }
    
    // Fonction pour trouver le prochain trip après une heure donnée
    int find_next_trip_index_after_time(list<string> trip_ids, int target_time) {
        loop i from: 0 to: length(trip_ids) - 1 {
            string trip_id <- trip_ids[i];
            list<pair<string, int>> sequence <- get_trip_sequence(trip_id);
            if length(sequence) > 0 {
                int departure_time <- sequence[0].value;
                if departure_time >= target_time {
                    return i;
                }
            }
        }
        return length(trip_ids);
    }
    
    // Conversion secondes -> HH:MM:SS
    string convert_seconds_to_time(int seconds) {
        int hours <- seconds div 3600;
        int minutes <- (seconds mod 3600) div 60;
        int secs <- seconds mod 60;
        
        string h_str <- hours < 10 ? "0" + hours : "" + hours;
        string m_str <- minutes < 10 ? "0" + minutes : "" + minutes;
        string s_str <- secs < 10 ? "0" + secs : "" + secs;
        
        return h_str + ":" + m_str + ":" + s_str;
    }
}

// ==================== AGENTS ====================

species bus_route {
    string route_name;
    string osm_id;
    string route_type;
    string highway_type;
    float length_meters;
    
    aspect default {
        if shape != nil {
            rgb route_color <- #blue;
            if route_type = "bus" {
                route_color <- #blue;
            } else if route_type = "tram" {
                route_color <- #orange;
            } else if route_type = "subway" {
                route_color <- #purple;
            } else {
                route_color <- #gray;
            }
            draw shape color: route_color width: 2;
        }
    }
}

species bus_stop {
    string stopId <- "";
    string stop_name <- "";
    string closest_route_id <- "";
    float closest_route_dist <- -1.0;
    bool is_matched <- false;
    string is_matched_str <- "FALSE";
    
    // VARIABLES POUR LANCEMENT VÉHICULES (adaptées du modèle Toulouse)
    list<string> my_trip_ids;  // trips partant de cet arrêt
    map<string, int> trip_departure_times;  // trip_id -> heure départ
    int current_trip_index <- 0;
    
    aspect default {
        rgb stop_color <- is_matched ? #green : #red;
        draw circle(100.0) color: stop_color;
    }
    
    // INITIALISATION DES TRIPS DE CET ARRÊT
    reflex init_trips when: cycle = 1 {
        my_trip_ids <- [];
        trip_departure_times <- map<string, int>([]);
        
        // Identifier les trips qui partent de cet arrêt
        loop trip_id over: trip_to_sequence.keys {
            list<pair<string, int>> sequence <- trip_to_sequence[trip_id];
            if length(sequence) > 0 and sequence[0].key = self.stopId {
                add trip_id to: my_trip_ids;
                trip_departure_times[trip_id] <- sequence[0].value;
            }
        }
        
        // Trier les trips par heure de départ
        my_trip_ids <- my_trip_ids sort_by (trip_departure_times[each]);
        
        // Saut à l'heure de simulation choisie
        if length(my_trip_ids) > 0 {
            current_trip_index <- world.find_next_trip_index_after_time(my_trip_ids, simulation_start_time);
            if debug_mode and current_trip_index < length(my_trip_ids) {
                write "🕐 Stop " + stopId + ": " + length(my_trip_ids) + " trips, premier index: " + current_trip_index;
            }
        }
    }
    
    // LANCEMENT DES VÉHICULES (logique adaptée du modèle Toulouse)
    reflex launch_bus when: (current_trip_index < length(my_trip_ids)) {
        string trip_id <- my_trip_ids[current_trip_index];
        int departure_time <- trip_departure_times[trip_id];
        
        if (current_seconds_mod >= departure_time) {
            // Vérifier que le trip a une route assignée
            string route_osm_id <- world.get_trip_dominant_route(trip_id);
            
            if route_osm_id != nil and route_graphs contains_key route_osm_id {
                list<pair<bus_stop, int>> trip_sequence <- world.get_trip_stops_sequence(trip_id);
                
                if length(trip_sequence) > 1 {
                    create bus with: [
                        trip_sequence:: trip_sequence,
                        current_stop_index:: 0,
                        trip_id:: trip_id,
                        route_osm_id:: route_osm_id,
                        location:: trip_sequence[0].key.location,
                        target_location:: trip_sequence[1].key.location,
                        local_network:: route_graphs[route_osm_id],
                        speed:: 10.0 * step,  // Vitesse initiale compensée par step
                        creation_time:: current_seconds_mod
                    ];
                    
                    if debug_mode {
                        string formatted_time <- world.convert_seconds_to_time(departure_time);
                        write "🚌 Véhicule créé pour trip " + trip_id + " à " + formatted_time;
                    }
                }
            }
            
            current_trip_index <- current_trip_index + 1;
        }
    }
}

species bus skills: [moving] {
    // VARIABLES DE BASE
    list<pair<bus_stop, int>> trip_sequence;  // Séquence arrêts avec horaires
    int current_stop_index;
    point target_location;
    string trip_id;
    string route_osm_id;
    graph local_network;
    float speed;
    int creation_time;
    int current_local_time;
    bool waiting_at_stop <- true;
    
    // VARIABLES NAVIGATION PRÉCISE (adaptées du modèle Toulouse)
    list<point> travel_points;
    list<float> traveled_dist_list;
    int travel_shape_idx <- 0;
    point moving_target;
    bool is_stopping -> moving_target = nil;
    float close_dist <- 15.0 #m;
    float min_dist_to_move <- 10.0 #m;
    
    // STATISTIQUES PONCTUALITÉ
    list<int> arrival_time_diffs <- [];
    
    init {
        // Initialisation navigation précise
        if route_polylines contains_key route_osm_id {
            geometry polyline <- route_polylines[route_osm_id];
            if polyline != nil {
                travel_points <- polyline.points;
                if route_cumulative_distances contains_key route_osm_id {
                    traveled_dist_list <- route_cumulative_distances[route_osm_id];
                }
            }
        }
        
        // Démarrer au premier point
        if length(travel_points) > 0 {
            location <- travel_points[0];
        }
    }
    
    reflex update_time {
        current_local_time <- int(current_date - date([1970,1,1,0,0,0])) mod 86400;
    }
    
    // ATTENTE À L'ARRÊT
    reflex wait_at_stop when: waiting_at_stop {
        if current_stop_index < length(trip_sequence) {
            int scheduled_time <- trip_sequence[current_stop_index].value;
            if current_local_time >= scheduled_time {
                do calculate_segment_speed;
                waiting_at_stop <- false;
            }
        }
    }
    
    // CALCUL VITESSE PAR SEGMENT
    action calculate_segment_speed {
        if current_stop_index >= length(trip_sequence) - 1 {
            return;
        }
        
        int current_time <- trip_sequence[current_stop_index].value;
        int next_time <- trip_sequence[current_stop_index + 1].value;
        int segment_time <- next_time - current_time;
        
        if segment_time <= 0 {
            speed <- 10.0 * step;
            return;
        }
        
        // Distance euclidienne entre arrêts (approximation)
        point current_pos <- trip_sequence[current_stop_index].key.location;
        point next_pos <- trip_sequence[current_stop_index + 1].key.location;
        float segment_distance <- (current_pos distance_to next_pos) * 1.3;  // Facteur détour
        
        float vitesse_reelle <- segment_distance / segment_time;
        float vitesse_compensee <- vitesse_reelle * step;
        
        speed <- max(3.0 * step, min(vitesse_compensee, 25.0 * step));
    }
    
    // MOUVEMENT PRÉCIS
    reflex move when: not is_stopping {
        do goto target: moving_target speed: speed;
        if location distance_to moving_target < close_dist {
            location <- moving_target;
            moving_target <- nil;
        }
    }
    
    // SUIVI DE ROUTE
    reflex follow_route when: is_stopping {
        // Vérifier arrivée à l'arrêt suivant
        if current_stop_index < length(trip_sequence) - 1 {
            point next_stop_pos <- trip_sequence[current_stop_index + 1].key.location;
            float dist_to_next_stop <- location distance_to next_stop_pos;
            
            if dist_to_next_stop <= close_dist {
                do arrive_at_stop;
                return;
            }
        } else {
            // Terminus atteint
            if debug_mode {
                write "🏁 Trip " + trip_id + " terminé. Écarts: " + arrival_time_diffs;
            }
            do die;
            return;
        }
        
        // Vérifier heure de départ
        int departure_time <- trip_sequence[current_stop_index].value;
        if current_local_time < departure_time {
            return;
        }
        
        // Navigation le long de la route
        if length(travel_points) > 0 and travel_shape_idx < length(travel_points) - 1 {
            float target_move_dist <- min_dist_to_move * step;
            
            int finding_from <- travel_shape_idx;
            loop i from: travel_shape_idx + 1 to: length(travel_points) - 1 {
                travel_shape_idx <- i;
                if length(traveled_dist_list) > i and length(traveled_dist_list) > finding_from {
                    float moved_dist <- traveled_dist_list[i] - traveled_dist_list[finding_from];
                    if moved_dist >= target_move_dist {
                        break;
                    }
                }
            }
            
            point next_target <- travel_points[travel_shape_idx];
            if moving_target != next_target {
                moving_target <- next_target;
            }
        }
    }
    
    // ARRIVÉE À UN ARRÊT
    action arrive_at_stop {
        // Calcul écart horaire
        int expected_time <- trip_sequence[current_stop_index + 1].value;
        int actual_time <- current_local_time;
        int time_diff <- expected_time - actual_time;
        
        arrival_time_diffs <- arrival_time_diffs + [time_diff];
        
        // Passer à l'arrêt suivant
        current_stop_index <- current_stop_index + 1;
        if current_stop_index < length(trip_sequence) {
            target_location <- trip_sequence[current_stop_index].key.location;
            waiting_at_stop <- true;
        }
    }
    
    aspect default {
        rgb vehicle_color <- #red;
        draw rectangle(80, 120) color: vehicle_color rotate: heading;
    }
}

// ==================== EXPERIMENT ====================

experiment bus_simulation type: gui {
    parameter "Debug Mode" var: debug_mode category: "Configuration";
    parameter "Heure début (h)" var: starting_date category: "Temporal" min: date("2024-01-01T06:00:00") max: date("2024-01-01T22:00:00");
    
    output {
        display "Simulation Transport" background: #white type: 2d {
            species bus_route aspect: default;
            species bus_stop aspect: default;
            species bus aspect: default;
        }
        
        display "Monitoring" {
            chart "Véhicules" type: series {
                data "Nb véhicules" value: length(bus) color: #blue;
            }
        }
        
        monitor "Véhicules actifs" value: length(bus);
        monitor "Heure simulation" value: convert_seconds_to_time(current_seconds_mod);
        monitor "Trips traités" value: sum(bus_stop collect each.current_trip_index);
    }
}