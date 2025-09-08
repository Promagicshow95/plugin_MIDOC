model GTFS_OSM_Hybrid_Realistic

global {
    // === FICHIERS GTFS ===
    gtfs_file gtfs_f <- gtfs_file("../../includes/hanoi_gtfs_pm");
    shape_file boundary_shp <- shape_file("../../includes/ShapeFileHanoishp.shp");
    geometry shape <- envelope(boundary_shp);

    // === CONFIGURATION OSM ===
    point top_left <- CRS_transform({0,0}, "EPSG:4326").location;
    point bottom_right <- CRS_transform({shape.width, shape.height}, "EPSG:4326").location;
    string osm_address <- "http://overpass-api.de/api/xapi_meta?*[bbox=" + top_left.x + "," + bottom_right.y + "," + bottom_right.x + "," + top_left.y + "]";
    
    map<string, list> osm_data_to_generate <- [
        "highway"::[],     // Routes
        "railway"::[],     // Voies ferrées  
        "route"::[],       // Relations route
        "cycleway"::[]     // Pistes cyclables
    ];

    // === PARAMÈTRES SIMULATION ===
    date min_date_gtfs <- starting_date_gtfs(gtfs_f);
    date max_date_gtfs <- ending_date_gtfs(gtfs_f);
    date starting_date <- date("2018-01-01T08:00:00");
    float step <- 10 #s;
    int time_24h -> int(current_date - date([1970,1,1,0,0,0])) mod 86400;
    int current_seconds_mod <- 0;
    int simulation_start_time;

    // === VARIABLES RÉSEAU ===
    list<int> gtfs_route_types <- [];  // Types trouvés dans GTFS
    graph global_network;              // Réseau de navigation global
    map<int, graph> networks_by_type;  // Réseaux par type de transport
    
    // === PARAMÈTRES MATCHING ===
    int grid_size <- 300;
    list<float> search_radii <- [100.0, 300.0, 500.0];
    list<pair<int,int>> neighbors <- [
        {0,0}, {-1,0}, {1,0}, {0,-1}, {0,1},
        {-1,-1}, {-1,1}, {1,-1}, {1,1}
    ];
    
    // === STATISTIQUES ===
    int nb_stops_matched <- 0;
    int nb_stops_total <- 0;
    map<int, int> routes_by_type <- [];
    map<string, string> trip_to_route_mapping <- [];

    init {
        write "=== MODÈLE HYBRIDE GTFS + OSM ===";
        simulation_start_time <- (starting_date.hour * 3600) + (starting_date.minute * 60) + starting_date.second;
        
        // 1. Créer les stops GTFS et identifier les types
        write "📍 Création des stops GTFS...";
        create bus_stop from: gtfs_f;
        nb_stops_total <- length(bus_stop);
        gtfs_route_types <- remove_duplicates(bus_stop collect each.routeType);
        write "Types de transport GTFS trouvés : " + gtfs_route_types;
        
        // 2. Créer le réseau OSM filtré
        write "🛤️ Création du réseau OSM filtré...";
        do create_filtered_osm_network;
        
        // 3. Créer les graphes de navigation
        write "🗺️ Création des graphes de navigation...";
        do create_navigation_graphs;
        
        // 4. Associer les stops aux routes OSM
        write "🔗 Association stops ↔ routes OSM...";
        do match_stops_to_routes;
        
        // 5. Créer les mappings trip → route
        write "📋 Création mappings trip → route...";
        do create_trip_mappings;
        
        // 6. Affichage des statistiques
        do display_statistics;
    }
    
    // === ACTION : Créer le réseau OSM filtré par types GTFS ===
    action create_filtered_osm_network {
        file<geometry> osm_geometries <- osm_file<geometry>(osm_address, osm_data_to_generate);
        write "Géométries OSM chargées : " + length(osm_geometries);
        
        loop geom over: osm_geometries {
            if length(geom.points) > 1 {
                int route_type_num <- get_osm_route_type(geom);
                
                // Filtrer seulement les types présents dans GTFS
                if (route_type_num in gtfs_route_types) {
                    do create_network_route(geom, route_type_num);
                    
                    // Compter par type
                    if (routes_by_type contains_key route_type_num) {
                        routes_by_type[route_type_num] <- routes_by_type[route_type_num] + 1;
                    } else {
                        routes_by_type[route_type_num] <- 1;
                    }
                }
            }
        }
        
        write "Routes OSM créées (filtrées) : " + length(network_route);
        loop route_type over: routes_by_type.keys {
            write "  Type " + route_type + " : " + routes_by_type[route_type] + " routes";
        }
    }
    
    // === FONCTION : Déterminer le type de route OSM ===
    int get_osm_route_type(geometry geom) {
        // Bus
        if ((geom.attributes["gama_bus_line"] != nil) 
            or (geom.attributes["route"] = "bus") 
            or (geom.attributes["highway"] = "busway")) {
            return 3;
        }
        // Tram
        else if (geom.attributes["railway"] = "tram") {
            return 0;
        }
        // Métro/Subway
        else if (geom.attributes["railway"] = "subway" or
                 geom.attributes["route"] = "subway" or
                 geom.attributes["route_master"] = "subway" or
                 geom.attributes["railway"] = "metro" or
                 geom.attributes["route"] = "metro") {
            return 1;
        }
        // Train/Railway
        else if (geom.attributes["railway"] != nil 
                and !(geom.attributes["railway"] in ["abandoned", "platform", "disused"])) {
            return 2;
        }
        // Routes génériques pour les bus si pas d'infrastructure spécialisée
        else if (geom.attributes["highway"] != nil and
                 geom.attributes["highway"] in ["primary", "secondary", "tertiary", "trunk", "residential"]) {
            return 3; // Considérer comme utilisable par les bus
        }
        else {
            return -1; // Non utilisé
        }
    }
    
    // === ACTION : Créer une route réseau ===
    action create_network_route(geometry geom, int route_type_num) {
        string route_type_name <- get_route_type_name(route_type_num);
        rgb route_color <- get_route_color(route_type_num);
        string name <- (geom.attributes["name"] as string);
        string osm_id <- (geom.attributes["osm_id"] as string);
        
        create network_route with: [
            shape::geom,
            route_type::route_type_name,
            routeType_num::route_type_num,
            route_color::route_color,
            name::name,
            osm_id::osm_id
        ];
    }
    
    // === FONCTIONS UTILITAIRES ===
    string get_route_type_name(int type) {
        switch type {
            match 0 { return "tram"; }
            match 1 { return "subway"; }
            match 2 { return "railway"; }
            match 3 { return "bus"; }
            default { return "other"; }
        }
    }
    
    rgb get_route_color(int type) {
        switch type {
            match 0 { return #orange; }    // Tram
            match 1 { return #red; }       // Métro
            match 2 { return #green; }     // Train
            match 3 { return #blue; }      // Bus
            default { return #gray; }
        }
    }
    
    // === ACTION : Créer les graphes de navigation ===
    action create_navigation_graphs {
        // Graphe global
        global_network <- as_edge_graph(network_route);
        write "Graphe global créé : " + length(global_network.vertices) + " sommets, " + 
              length(global_network.edges) + " arêtes";
        
        // Graphes par type
        loop route_type over: gtfs_route_types {
            list<network_route> routes_of_type <- network_route where (each.routeType_num = route_type);
            if (length(routes_of_type) > 0) {
                networks_by_type[route_type] <- as_edge_graph(routes_of_type);
                write "Graphe type " + route_type + " : " + length(networks_by_type[route_type].vertices) + " sommets";
            }
        }
    }
    
    // === ACTION : Associer stops aux routes OSM ===
    action match_stops_to_routes {
        // Attribution des zones spatiales
        ask bus_stop {
            zone_id <- (int(location.x / grid_size) * 100000) + int(location.y / grid_size);
        }
        ask network_route {
            point centroid <- shape.location;
            zone_id <- (int(centroid.x / grid_size) * 100000) + int(centroid.y / grid_size);
        }
        
        // Matching spatial
        ask bus_stop {
            do find_closest_route;
        }
        
        nb_stops_matched <- length(bus_stop where each.is_matched);
        write "Stops associés : " + nb_stops_matched + "/" + nb_stops_total;
    }
    
    // === ACTION : Créer les mappings trip → route ===
    action create_trip_mappings {
        map<string, list<string>> temp_mapping <- [];
        
        // Collecter les associations trip → osm_id
        ask bus_stop where (each.is_matched) {
            loop trip_id over: departureStopsInfo.keys {
                if (temp_mapping contains_key trip_id) {
                    temp_mapping[trip_id] <+ closest_route_id;
                } else {
                    temp_mapping[trip_id] <- [closest_route_id];
                }
            }
        }
        
        // Déterminer l'osm_id majoritaire par trip
        loop trip_id over: temp_mapping.keys {
            list<string> osm_ids <- temp_mapping[trip_id];
            map<string, int> counter <- [];
            
            loop osm_id over: osm_ids {
                counter[osm_id] <- (counter contains_key osm_id) ? counter[osm_id] + 1 : 1;
            }
            
            string majority_osm_id;
            int max_count <- 0;
            
            loop osm_id over: counter.keys {
                if counter[osm_id] > max_count {
                    max_count <- counter[osm_id];
                    majority_osm_id <- osm_id;
                }
            }
            
            trip_to_route_mapping[trip_id] <- majority_osm_id;
        }
        
        write "Mappings trip → route créés : " + length(trip_to_route_mapping);
    }
    
    // === ACTION : Afficher les statistiques ===
    action display_statistics {
        write "\n=== STATISTIQUES FINALES ===";
        write "📍 Total stops GTFS : " + nb_stops_total;
        write "🔗 Stops associés : " + nb_stops_matched + " (" + round((nb_stops_matched/nb_stops_total)*100) + "%)";
        write "🛤️ Total routes OSM : " + length(network_route);
        write "📋 Mappings trip → route : " + length(trip_to_route_mapping);
        write "🗺️ Graphes créés : " + length(networks_by_type) + " par type + 1 global";
    }
    
    reflex update_time_every_cycle {
        current_seconds_mod <- time_24h;
    }
}

// === ESPÈCE : Arrêt de bus GTFS ===
species bus_stop skills: [TransportStopSkill] {
    // Variables de matching avec OSM
    string closest_route_id <- "";
    int closest_route_index <- -1;
    float closest_route_dist <- -1.0;
    int zone_id;
    bool is_matched <- false;
    
    // Variables GTFS originales
    list<string> ordered_trip_ids;
    int current_trip_index <- 0;
    
    // === ACTION : Trouver la route OSM la plus proche ===
    action find_closest_route {
        int zx <- int(location.x / grid_size);
        int zy <- int(location.y / grid_size);
        list<int> neighbor_zone_ids <- [];
        
        loop offset over: neighbors {
            int nx <- zx + offset[0];
            int ny <- zy + offset[1];
            neighbor_zone_ids <+ (nx * 100000 + ny);
        }

        bool found <- false;
        float best_dist <- #max_float;
        network_route best_route <- nil;
    
        // Recherche par rayons croissants
        loop radius over: search_radii {
            // D'abord dans la même zone avec le même type
            list<network_route> candidate_routes <- network_route where (
                (each.routeType_num = routeType) and (each.zone_id in neighbor_zone_ids)
            );
            
            if !empty(candidate_routes) {
                loop route over: candidate_routes {
                    float dist <- self distance_to route.shape;
                    if dist < best_dist {
                        best_dist <- dist;
                        best_route <- route;
                    }
                }
                
                if best_route != nil and best_dist <= radius {
                    closest_route_id <- best_route.osm_id;
                    closest_route_index <- best_route.index;
                    closest_route_dist <- best_dist;
                    is_matched <- true;
                    found <- true;
                    break;
                }
            }
        }
        
        // Fallback : recherche globale même type
        if !found {
            loop radius over: search_radii {
                list<network_route> candidate_routes2 <- network_route where (
                    each.routeType_num = routeType
                );
                
                if !empty(candidate_routes2) {
                    loop route2 over: candidate_routes2 {
                        float dist2 <- self distance_to route2.shape;
                        if dist2 < best_dist {
                            best_dist <- dist2;
                            best_route <- route2;
                        }
                    }
                    
                    if best_route != nil and best_dist <= radius {
                        closest_route_id <- best_route.osm_id;
                        closest_route_index <- best_route.index;
                        closest_route_dist <- best_dist;
                        is_matched <- true;
                        found <- true;
                        break;
                    }
                }
            }
        }
    }
    
    // === REFLEXES GTFS (logique originale adaptée) ===
    reflex init_order when: cycle = 1 {
        ordered_trip_ids <- keys(departureStopsInfo);
        if (ordered_trip_ids != nil) {
            current_trip_index <- find_next_trip_index_after_time(simulation_start_time);
        }
    }
    
    int find_next_trip_index_after_time(int target_time) {
        if (ordered_trip_ids = nil or length(ordered_trip_ids) = 0) { 
            return 0; 
        }
        
        if (departureStopsInfo = nil) {
            return 0;
        }
        
        loop i from: 0 to: length(ordered_trip_ids) - 1 {
            string trip_id <- ordered_trip_ids[i];
            
            if (departureStopsInfo contains_key trip_id) {
                list<pair<bus_stop, string>> trip_info <- departureStopsInfo[trip_id];
                
                if (trip_info != nil and length(trip_info) > 0) {
                    int departure_time <- int(trip_info[0].value);
                    
                    if (departure_time >= target_time) {
                        return i;
                    }
                }
            }
        }
        return length(ordered_trip_ids);
    }

    reflex launch_bus when: (departureStopsInfo != nil and current_trip_index < length(ordered_trip_ids)) {
        string trip_id <- ordered_trip_ids[current_trip_index];
        list<pair<bus_stop, string>> trip_info <- departureStopsInfo[trip_id];
        string departure_time <- trip_info[0].value;

        if (current_seconds_mod >= int(departure_time)) {
            // Utiliser le réseau OSM au lieu des fake shapes
            if (is_matched and networks_by_type contains_key routeType) {
                create hybrid_bus with: [
                    departureStopsInfo:: trip_info,
                    current_stop_index:: 0,
                    location:: trip_info[0].key.location,
                    trip_id:: trip_id,
                    route_type:: routeType,
                    navigation_network:: networks_by_type[routeType],
                    assigned_route_id:: closest_route_id,
                    creation_time:: current_seconds_mod
                ];
                current_trip_index <- current_trip_index + 1;
            }
        }
    }

    aspect base {
        draw circle(50) color: is_matched ? #blue : #red;
    }
    
    aspect detailed {
        draw circle(50) color: is_matched ? #blue : #red;
        if is_matched {
            draw "✓" color: #white size: 8 at: location;
        } else {
            draw "✗" color: #white size: 8 at: location;
        }
    }
}

// === ESPÈCE : Route réseau OSM ===
species network_route {
    geometry shape;
    string route_type;
    int routeType_num;
    string name;
    string osm_id;
    rgb route_color;
    int zone_id;
    
    aspect base {
        draw shape color: route_color width: 2;
    }
    
    aspect detailed {
        draw shape color: route_color width: 3;
        if name != nil and name != "" {
            draw name color: #black size: 6 at: shape.location;
        }
    }
}

// === ESPÈCE : Bus hybride circulant sur réseau OSM ===
species hybrid_bus skills: [moving] {
    // Variables GTFS
    list<pair<bus_stop, string>> departureStopsInfo;
    int current_stop_index;
    string trip_id;
    int route_type;
    int creation_time;
    int current_local_time;
    list<int> arrival_time_diffs_pos <- [];
    list<int> arrival_time_diffs_neg <- [];
    bool waiting_at_stop <- true;
    
    // Variables réseau OSM
    graph navigation_network;
    string assigned_route_id;
    float speed;
    point current_target;
    path current_path;
    float realistic_speed_factor <- 1.0;
    
    // Vitesses moyennes par type (m/s)
    map<int, float> avg_speeds_ms <- [
        0::7.0,   // Tram : 25 km/h
        1::10.0,  // Métro : 36 km/h
        2::16.0,  // Train : 58 km/h
        3::5.0    // Bus : 18 km/h
    ];
    
    init {
        // Vitesse réaliste selon le type
        float base_speed <- avg_speeds_ms contains_key route_type ? avg_speeds_ms[route_type] : 5.0;
        realistic_speed_factor <- gauss(1.0, 0.15); // ±15% variation
        realistic_speed_factor <- max(0.8, min(realistic_speed_factor, 1.2));
        speed <- base_speed * realistic_speed_factor * step;
        
        write "🚌 Bus " + trip_id + " créé (type " + route_type + ", vitesse: " + round(speed/step*3.6) + " km/h)";
    }

    reflex update_time {
        current_local_time <- int(current_date - date([1970,1,1,0,0,0])) mod 86400;
    }

    reflex wait_at_stop when: waiting_at_stop {
        int stop_time <- departureStopsInfo[current_stop_index].value as int;
        
        if (current_local_time >= stop_time) {
            waiting_at_stop <- false;
            
            // Définir la prochaine destination
            if (current_stop_index < length(departureStopsInfo) - 1) {
                current_target <- departureStopsInfo[current_stop_index + 1].key.location;
                
                // Calculer le chemin sur le réseau OSM
                if (navigation_network != nil) {
                    current_path <- path_between(navigation_network, location, current_target);
                    if (current_path = nil) {
                        // Fallback : navigation directe
                        write "⚠️ Pas de chemin trouvé pour " + trip_id + ", navigation directe";
                    }
                }
            }
        }
    }
    
    reflex move_on_network when: not waiting_at_stop {
        if (current_target != nil) {
            float dist_to_target <- location distance_to current_target;
            
            // Arrivée détectée
            if (dist_to_target <= 20.0) {
                location <- current_target;
                do arrive_at_stop;
                return;
            }
            
            // Navigation sur le réseau ou directe
            if (current_path != nil) {
                do follow path: current_path speed: speed;
            } else {
                do goto target: current_target speed: speed;
            }
        }
    }
    
    action arrive_at_stop {
        if (current_stop_index + 1 >= length(departureStopsInfo)) {
            write "🏁 Bus " + trip_id + " terminé";
            do die;
            return;
        }
        
        // Calcul performance temporelle
        int expected_time <- departureStopsInfo[current_stop_index + 1].value as int;
        int actual_time <- current_local_time;
        int time_diff <- expected_time - actual_time;
        
        if (time_diff < 0) {
            arrival_time_diffs_neg << time_diff;
        } else {
            arrival_time_diffs_pos << time_diff;
        }
        
        // Progression
        current_stop_index <- current_stop_index + 1;
        if (current_stop_index < length(departureStopsInfo)) {
            waiting_at_stop <- true;
            current_target <- nil;
            current_path <- nil;
        } else {
            write "🏁 Bus " + trip_id + " terminé normalement";
            do die;
        }
    }

    aspect base {
        rgb vehicle_color;
        switch route_type {
            match 0 { vehicle_color <- #orange; }    // Tram
            match 1 { vehicle_color <- #red; }       // Métro
            match 2 { vehicle_color <- #green; }     // Train
            match 3 { vehicle_color <- #blue; }      // Bus
            default { vehicle_color <- #gray; }
        }
        draw rectangle(100, 150) color: vehicle_color rotate: heading;
    }
}

experiment GTFS_OSM_Hybrid type: gui {
    output {
        display "Réseau Hybride GTFS + OSM" {
            species network_route aspect: base;
            species bus_stop aspect: base;
            species hybrid_bus aspect: base;
            
            overlay position: {10, 10} size: {350 #px, 180 #px} background: #white transparency: 0.8 {
                draw "=== RÉSEAU HYBRIDE GTFS + OSM ===" at: {15#px, 20#px} color: #black font: font("Arial", 12, #bold);
                draw "🛤️ Routes OSM : " + length(network_route) at: {15#px, 45#px} color: #green;
                draw "📍 Stops GTFS : " + nb_stops_total at: {15#px, 65#px} color: #blue;
                draw "🔗 Stops associés : " + nb_stops_matched + " (" + round((nb_stops_matched/nb_stops_total)*100) + "%)" at: {15#px, 85#px} color: #blue;
                draw "📋 Mappings : " + length(trip_to_route_mapping) at: {15#px, 105#px} color: #black;
                draw "🚌 Bus actifs : " + length(hybrid_bus) at: {15#px, 125#px} color: #orange;
                draw "⏰ Heure sim : " + (current_seconds_mod / 3600) + "h" + ((current_seconds_mod mod 3600) / 60) + "m" at: {15#px, 145#px} color: #purple;
            }
        }

        display "Performance Temporelle" {
            chart "Ponctualité" type: series {
                data "Avance (s)" value: length(hybrid_bus) > 0 ? mean(hybrid_bus collect mean(each.arrival_time_diffs_pos)) : 0 color: #green;
                data "Retard (s)" value: length(hybrid_bus) > 0 ? mean(hybrid_bus collect mean(each.arrival_time_diffs_neg)) : 0 color: #red;
            }
        }
        
    }
}