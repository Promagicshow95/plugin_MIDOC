/**
 * Name: ModeleVehiculeMoveInReseauxShapeFile
 * Author: Adapted
 * Description: Réseau bus + stops avec algorithme robuste - Corrections `pair` variable
 */

model ModeleVehiculeMoveInReseauxShapeFile

global {
    // CONFIGURATION FICHIERS
    string results_folder <- "../../results/";
    string stops_folder <- "../../results/stopReseau/";
    
    file data_file <- shape_file("../../includes/shapeFileHanoishp.shp");
    geometry shape <- envelope(data_file);
    
    // VARIABLES STATISTIQUES
    int total_bus_routes <- 0;
    int total_bus_stops <- 0;
    int total_trips_found <- 0;
    int successful_conversions <- 0;
    int failed_trips <- 0;
    bool debug_mode <- true;
    
    // STRUCTURES OPTIMISÉES DEPARTUREINFO
    map<string, map<string, list<pair<string, int>>>> stop_to_all_trips;
    map<string, bus_stop> stopId_to_agent;
    map<string, list<pair<bus_stop, int>>> trip_to_agents_with_times;
    map<string, string> trip_to_osm_route;

    init {
        write "=== RÉSEAU BUS AVEC ALGORITHME ROBUSTE ===";
        
        do load_bus_network_robust;
        do load_gtfs_stops_from_shapefile;
        do build_optimized_departure_structures_robust;
        do display_final_statistics;
    }
    
    // CHARGEMENT RÉSEAU BUS
    action load_bus_network_robust {
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
                continue_loading <- false;
            }
        }
        
        total_bus_routes <- bus_routes_count;
        write "Routes chargées : " + bus_routes_count;
    }
    
    // CHARGEMENT ARRÊTS GTFS
    action load_gtfs_stops_from_shapefile {
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
            }
            
            write "Arrêts chargés : " + total_bus_stops;
            
        } catch {
            write "ERREUR chargement arrêts";
            total_bus_stops <- 0;
        }
    }
    
    // ALGORITHME ROBUSTE COMPLET
    action build_optimized_departure_structures_robust {
        write "\n3. CONSTRUCTION STRUCTURES AVEC ALGORITHME ROBUSTE";
        
        do pre_read_and_parse_json;
        
        if length(stop_to_all_trips) = 0 {
            write "ERREUR: Aucun trip trouvé - parsing échoué";
            return;
        }
        
        do build_stopId_to_agent_map;
        do convert_to_final_structure_by_trip;
        do build_trip_to_osm_mapping;
        
        write "Algorithme robuste terminé avec succès";
    }
    
    // PRÉ-LECTURE & PARSE JSON
    action pre_read_and_parse_json {
        write "ÉTAPE 1: Pré-lecture & parse unique";
        
        string json_filename <- stops_folder + "departure_stops_info_stopid.json";
        stop_to_all_trips <- map<string, map<string, list<pair<string, int>>>>([]);
        
        try {
            file json_f <- text_file(json_filename);
            string content <- string(json_f);
            map<string, unknown> json_data <- from_json(content);
            
            if !(json_data contains_key "departure_stops_info") {
                write "ERREUR: Clé 'departure_stops_info' manquante";
                return;
            }
            
            list<map<string, unknown>> stops_list <- list<map<string, unknown>>(json_data["departure_stops_info"]);
            write "JSON lu: " + length(stops_list) + " arrêts détectés";
            
            do process_stops_from_json(stops_list);
            
        } catch {
            write "ERREUR lecture/parsing JSON : " + json_filename;
        }
    }
    
    // TRAITEMENT STOPS JSON
    action process_stops_from_json(list<map<string, unknown>> stops_list) {
        write "ÉTAPE 2: Traitement " + length(stops_list) + " stops JSON";
        
        int processed_stops <- 0;
        
        loop stop_data over: stops_list {
            string stop_id <- string(stop_data["stopId"]);
            
            bool is_bus <- true;
            if stop_data contains_key "routeType" {
                int route_type <- int(stop_data["routeType"]);
                is_bus <- (route_type = 3);
                if !is_bus and debug_mode {
                    write "Stop " + stop_id + " ignoré (routeType=" + route_type + ")";
                }
            }
            
            if stop_id != nil and stop_id != "" and is_bus and 
               stop_data contains_key "departureStopsInfo" {
                
                processed_stops <- processed_stops + 1;
                
                if !(stop_to_all_trips contains_key stop_id) {
                    stop_to_all_trips[stop_id] <- map<string, list<pair<string, int>>>([]);
                }
                
                map<string, unknown> departure_info <- map<string, unknown>(stop_data["departureStopsInfo"]);
                do process_trips_from_stop(stop_id, departure_info);
            }
        }
        
        write "Stops traités: " + processed_stops + "/" + length(stops_list);
    }
    
    // TRAITEMENT TRIPS D'UN STOP
    action process_trips_from_stop(string stop_id, map<string, unknown> departure_info) {
        loop trip_id over: departure_info.keys {
            unknown trip_data <- departure_info[trip_id];
            
            list<pair<string, int>> normalized_trip <- normalize_trip_robust(trip_data, trip_id, stop_id);
            list<pair<string, int>> cleaned_trip <- clean_and_validate_trip(normalized_trip);
            
            if !empty(cleaned_trip) {
                stop_to_all_trips[stop_id][trip_id] <- cleaned_trip;
                total_trips_found <- total_trips_found + 1;
            } else {
                failed_trips <- failed_trips + 1;
                if debug_mode and failed_trips <= 3 {
                    write "Trip échoué: " + trip_id + " pour stop " + stop_id;
                }
            }
        }
    }
    
    // NORMALISATION ROBUSTE D'UN TRIP
    list<pair<string, int>> normalize_trip_robust(unknown trip_data, string trip_id, string stop_id) {
        list<pair<string, int>> result <- [];
        
        try {
            // CAS 1: TABLEAU DE PAIRES
            result <- try_parse_as_pair_array(trip_data);
            if !empty(result) {
                if debug_mode and total_trips_found < 3 {
                    write "Format détecté: Tableau de paires pour " + trip_id;
                }
                return result;
            }
            
            // CAS 2: TABLEAU APLATI
            result <- try_parse_as_flat_array(trip_data);
            if !empty(result) {
                if debug_mode and total_trips_found < 3 {
                    write "Format détecté: Tableau aplati pour " + trip_id;
                }
                return result;
            }
            
            // CAS 3: ÉLÉMENTS ENCODÉS EN CHAÎNE
            result <- try_parse_as_string_encoded(trip_data);
            if !empty(result) {
                if debug_mode and total_trips_found < 3 {
                    write "Format détecté: Éléments encodés pour " + trip_id;
                }
                return result;
            }
            
            // CAS 4: OBJET PAR ROUTE_KEY
            result <- try_parse_as_route_object(trip_data);
            if !empty(result) {
                if debug_mode and total_trips_found < 3 {
                    write "Format détecté: Objet route_key pour " + trip_id;
                }
                return result;
            }
            
            if debug_mode and failed_trips < 3 {
                string sample <- string(trip_data);
                if length(sample) > 100 {
                    sample <- copy(sample, 0, 100) + "...";
                }
                write "Format non reconnu pour " + trip_id + ": " + sample;
            }
            
        } catch {
            if debug_mode and failed_trips < 3 {
                write "Erreur normalisation trip " + trip_id;
            }
        }
        
        return result;
    }
    
    // CAS 1: TABLEAU DE PAIRES - CORRECTION VARIABLE NAMES
    list<pair<string, int>> try_parse_as_pair_array(unknown trip_data) {
        list<pair<string, int>> result <- [];
        
        try {
            list<unknown> array_data <- list<unknown>(trip_data);
            
            if length(array_data) > 0 {
                unknown first_element <- array_data[0];
                
                try {
                    list<unknown> first_element_data <- list<unknown>(first_element);
                    if length(first_element_data) >= 2 {
                        // Format tableau de paires détecté
                        loop element over: array_data {
                            try {
                                list<unknown> element_data <- list<unknown>(element);
                                if length(element_data) >= 2 {
                                    string sid <- string(element_data[0]);
                                    int time_sec <- parse_time_robust(string(element_data[1]));
                                    
                                    if sid != "" and time_sec > 0 {
                                        result <+ pair(sid, time_sec);
                                    }
                                }
                            } catch {
                                // Ignorer paire mal formée
                            }
                        }
                    }
                } catch {
                    // Pas des paires, essayer autre format
                }
            }
        } catch {
            // Essayer parsing string JSON
            try {
                string trip_str <- string(trip_data);
                unknown parsed <- from_json(trip_str);
                list<unknown> array_data <- list<unknown>(parsed);
                
                loop element over: array_data {
                    try {
                        list<unknown> element_data <- list<unknown>(element);
                        if length(element_data) >= 2 {
                            string sid <- string(element_data[0]);
                            int time_sec <- parse_time_robust(string(element_data[1]));
                            
                            if sid != "" and time_sec > 0 {
                                result <+ pair(sid, time_sec);
                            }
                        }
                    } catch {
                        // Ignorer
                    }
                }
            } catch {
                // Pas un string JSON valide
            }
        }
        
        return result;
    }
    
    // CAS 2: TABLEAU APLATI
    list<pair<string, int>> try_parse_as_flat_array(unknown trip_data) {
        list<pair<string, int>> result <- [];
        
        try {
            list<unknown> array_data <- list<unknown>(trip_data);
            
            if length(array_data) > 0 and (length(array_data) mod 2) = 0 {
                bool is_scalar <- true;
                if length(array_data) > 0 {
                    try {
                        list<unknown> test_element <- list<unknown>(array_data[0]);
                        is_scalar <- false;
                    } catch {
                        is_scalar <- true;
                    }
                }
                
                if is_scalar {
                    loop i from: 0 to: (length(array_data) - 1) step: 2 {
                        try {
                            string sid <- string(array_data[i]);
                            int time_sec <- parse_time_robust(string(array_data[i + 1]));
                            
                            if sid != "" and time_sec > 0 {
                                result <+ pair(sid, time_sec);
                            }
                        } catch {
                            // Ignorer paire mal formée
                        }
                    }
                }
            }
        } catch {
            // Pas un tableau aplati
        }
        
        return result;
    }
    
    // CAS 3: ÉLÉMENTS ENCODÉS EN CHAÎNE
    list<pair<string, int>> try_parse_as_string_encoded(unknown trip_data) {
        list<pair<string, int>> result <- [];
        
        try {
            list<unknown> array_data <- list<unknown>(trip_data);
            
            loop element over: array_data {
                string element_str <- string(element);
                
                if element_str contains ":" {
                    list<string> parts <- element_str split_with ":";
                    if length(parts) >= 2 {
                        string sid <- parts[0];
                        int time_sec <- parse_time_robust(parts[1]);
                        
                        if sid != "" and time_sec > 0 {
                            result <+ pair(sid, time_sec);
                        }
                    }
                }
                else if element_str contains "[" and element_str contains "," and element_str contains "]" {
                    try {
                        unknown parsed_element <- from_json(element_str);
                        list<unknown> element_array <- list<unknown>(parsed_element);
                        
                        if length(element_array) >= 2 {
                            string sid <- string(element_array[0]);
                            int time_sec <- parse_time_robust(string(element_array[1]));
                            
                            if sid != "" and time_sec > 0 {
                                result <+ pair(sid, time_sec);
                            }
                        }
                    } catch {
                        // Pas JSON valide
                    }
                }
            }
        } catch {
            // Pas des éléments encodés
        }
        
        return result;
    }
    
    // CAS 4: OBJET PAR ROUTE_KEY
    list<pair<string, int>> try_parse_as_route_object(unknown trip_data) {
        list<pair<string, int>> result <- [];
        
        try {
            map<string, unknown> object_data <- map<string, unknown>(trip_data);
            
            int sequence_counter <- 0;
            int base_time <- 28800;
            
            loop route_key over: object_data.keys {
                try {
                    list<string> details <- list<string>(object_data[route_key]);
                    
                    loop detail over: details {
                        string sid <- "";
                        int time_sec <- 0;
                        
                        if detail contains ":" {
                            list<string> parts <- detail split_with ":";
                            if length(parts) >= 2 {
                                sid <- parts[0];
                                time_sec <- parse_time_robust(parts[1]);
                            }
                        }
                        else {
                            sid <- detail;
                            time_sec <- base_time + (sequence_counter * 180);
                            sequence_counter <- sequence_counter + 1;
                        }
                        
                        if sid != "" and time_sec > 0 {
                            result <+ pair(sid, time_sec);
                        }
                    }
                    
                } catch {
                    // Ignorer route_key problématique
                }
            }
            
        } catch {
            // Pas un objet
        }
        
        return result;
    }
    
    // PARSING DU TEMPS ROBUSTE
    int parse_time_robust(string time_str) {
        if time_str = nil or time_str = "" {
            return 0;
        }
        
        try {
            int direct_int <- int(time_str);
            return direct_int;
        } catch {
            if time_str contains ":" {
                list<string> parts <- time_str split_with ":";
                if length(parts) >= 2 {
                    try {
                        int hours <- int(parts[0]);
                        int minutes <- int(parts[1]);
                        int seconds <- length(parts) >= 3 ? int(parts[2]) : 0;
                        
                        return hours * 3600 + minutes * 60 + seconds;
                    } catch {
                        return 0;
                    }
                }
            }
            
            try {
                float time_float <- float(time_str);
                return int(time_float);
            } catch {
                return 0;
            }
        }
    }
    
    // NETTOYAGE & VALIDATION
    list<pair<string, int>> clean_and_validate_trip(list<pair<string, int>> trip) {
        list<pair<string, int>> cleaned <- [];
        list<string> seen_stops <- [];
        
        loop stop_time over: trip {
            string sid <- stop_time.key;
            int time_sec <- stop_time.value;
            
            if sid != "" and time_sec > 0 and !(sid in seen_stops) {
                cleaned <+ pair(sid, time_sec);
                seen_stops <+ sid;
            }
        }
        
        if length(cleaned) < 2 {
            return [];
        }
        
        return cleaned;
    }
    
    // MAP DE CONVERSION STOPID -> AGENT
    action build_stopId_to_agent_map {
        write "ÉTAPE 9: Construction map stopId -> agent";
        
        stopId_to_agent <- map<string, bus_stop>([]);
        
        ask bus_stop {
            if stopId != nil and stopId != "" {
                stopId_to_agent[stopId] <- self;
            }
        }
        
        write "Conversions créées: " + length(stopId_to_agent);
    }
    
    // CONVERSION VERS STRUCTURE FINALE PAR TRIP
    action convert_to_final_structure_by_trip {
        write "ÉTAPE 10: Conversion vers structure finale";
        
        trip_to_agents_with_times <- map<string, list<pair<bus_stop, int>>>([]);
        successful_conversions <- 0;
        
        loop stop_id over: stop_to_all_trips.keys {
            map<string, list<pair<string, int>>> trips_from_stop <- stop_to_all_trips[stop_id];
            
            loop trip_id over: trips_from_stop.keys {
                if !(trip_to_agents_with_times contains_key trip_id) {
                    list<pair<string, int>> schedule <- trips_from_stop[trip_id];
                    list<pair<bus_stop, int>> agents_with_times <- [];
                    
                    loop stop_time_data over: schedule {
                        string stop_id_in_trip <- stop_time_data.key;
                        int time <- stop_time_data.value;
                        
                        if stopId_to_agent contains_key stop_id_in_trip {
                            bus_stop stop_agent <- stopId_to_agent[stop_id_in_trip];
                            agents_with_times <+ pair(stop_agent, time);
                        }
                    }
                    
                    if !empty(agents_with_times) {
                        trip_to_agents_with_times[trip_id] <- agents_with_times;
                        successful_conversions <- successful_conversions + 1;
                    }
                }
            }
        }
        
        write "Trips convertis: " + successful_conversions;
    }
    
    // LIAISON TRIP -> ROUTE OSM
    action build_trip_to_osm_mapping {
        write "ÉTAPE 11: Construction liaison trip -> route OSM";
        
        trip_to_osm_route <- map<string, string>([]);
        int successful_mappings <- 0;
        
        loop trip_id over: trip_to_agents_with_times.keys {
            list agents_route <- trip_to_agents_with_times[trip_id];
            
            map<string, int> osm_votes <- map<string, int>([]);
            
            loop agent_data over: agents_route {
                pair<bus_stop, int> stop_time_data <- agent_data;
                bus_stop stop_agent <- stop_time_data.key;
                
                if stop_agent.closest_route_id != nil and stop_agent.closest_route_id != "" {
                    string osm_id <- stop_agent.closest_route_id;
                    osm_votes[osm_id] <- (osm_votes contains_key osm_id) ? osm_votes[osm_id] + 1 : 1;
                }
            }
            
            if !empty(osm_votes) {
                string majority_osm <- "";
                int max_votes <- 0;
                
                loop osm_id over: osm_votes.keys {
                    if osm_votes[osm_id] > max_votes {
                        max_votes <- osm_votes[osm_id];
                        majority_osm <- osm_id;
                    }
                }
                
                if majority_osm != "" {
                    trip_to_osm_route[trip_id] <- majority_osm;
                    successful_mappings <- successful_mappings + 1;
                }
            }
        }
        
        write "Trips liés OSM: " + successful_mappings;
    }
    
    // APIS D'ACCÈS
    list get_trip_route(string trip_id) {
        if trip_to_agents_with_times contains_key trip_id {
            return trip_to_agents_with_times[trip_id];
        }
        return [];
    }
    
    bus_stop get_stop_agent(string stop_id) {
        if stopId_to_agent contains_key stop_id {
            return stopId_to_agent[stop_id];
        }
        return nil;
    }
    
    list get_all_trip_ids {
        return trip_to_agents_with_times.keys;
    }
    
    string get_osm_route_for_trip(string trip_id) {
        if trip_to_osm_route contains_key trip_id {
            return trip_to_osm_route[trip_id];
        }
        return "";
    }
    
    // STATISTIQUES FINALES
    action display_final_statistics {
        write "\n=== STATISTIQUES ALGORITHME ROBUSTE ===";
        write "Routes Bus : " + total_bus_routes;
        write "Arrêts GTFS : " + total_bus_stops;
        write "Trips trouvés : " + total_trips_found;
        write "Trips échoués : " + failed_trips;
        write "Conversions réussies : " + successful_conversions;
        
        if (total_trips_found + failed_trips) > 0 {
            write "Taux de succès : " + int((total_trips_found/(total_trips_found + failed_trips)) * 100) + "%";
        }
        
        write "\nStructures en mémoire :";
        write "  - stop_to_all_trips : " + length(stop_to_all_trips);
        write "  - stopId_to_agent : " + length(stopId_to_agent);
        write "  - trip_to_agents_with_times : " + length(trip_to_agents_with_times);
        write "  - trip_to_osm_route : " + length(trip_to_osm_route);
        
        if !empty(trip_to_agents_with_times) {
            string sample_trip <- first(trip_to_agents_with_times.keys);
            list sample_route <- trip_to_agents_with_times[sample_trip];
            string osm_route <- get_osm_route_for_trip(sample_trip);
            
            write "\nExemple de réussite :";
            write "  Trip : " + sample_trip;
            write "  Arrêts : " + length(sample_route);
            write "  Route OSM : " + osm_route;
            
            if length(sample_route) > 0 {
                write "  Séquence (3 premiers) :";
                int max_display <- min(3, length(sample_route));
                loop i from: 0 to: (max_display - 1) {
                    pair<bus_stop, int> stop_time_info <- sample_route[i];
                    bus_stop stop <- stop_time_info.key;
                    int time <- stop_time_info.value;
                    write "    " + stop.stopId + " à " + time + "s";
                }
            }
        } else {
            write "\nAUCUN SUCCÈS - Problème de correspondance ou parsing complet échoué";
            write "Vérifiez les logs de debug pour identifier le format manquant";
        }
    }
}

// AGENTS
species bus_route {
    string route_name;
    string osm_id;
    string route_type;
    string highway_type;
    float length_meters;
    
    aspect default {
        if shape != nil {
            draw shape color: #blue width: 1.5;
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
    
    aspect default {
        draw circle(100.0) color: is_matched ? #green : #red;
        
        int trips_count <- 0;
        loop trip_id over: world.get_all_trip_ids() {
            list<pair<bus_stop, int>> route <- world.get_trip_route(trip_id);
            loop stop_data over: route {
                if stop_data.key = self {
                    trips_count <- trips_count + 1;
                    break;
                }
            }
        }
        
        if trips_count > 0 {
            draw circle(150.0) border: #blue width: 2;
            draw string(trips_count) at: location + {0, 200} color: #blue size: 12;
        }
    }
}

// EXPERIMENT
experiment network_robust_fixed type: gui {
    
    action reload_all {
        ask world {
            ask bus_route { do die; }
            ask bus_stop { do die; }
            
            total_bus_routes <- 0;
            total_bus_stops <- 0;
            total_trips_found <- 0;
            successful_conversions <- 0;
            failed_trips <- 0;
            
            stop_to_all_trips <- map<string, map<string, list<pair<string, int>>>>([]);
            stopId_to_agent <- map<string, bus_stop>([]);
            trip_to_agents_with_times <- map<string, list<pair<bus_stop, int>>>([]);
            trip_to_osm_route <- map<string, string>([]);
            
            do load_bus_network_robust;
            do load_gtfs_stops_from_shapefile;
            do build_optimized_departure_structures_robust;
            do display_final_statistics;
        }
    }
    
    user_command "Recharger" action: reload_all;
    
    output {
        display "ModeleVehiculeMoveInReseauxShapeFile" background: #white type: 2d {
            species bus_route aspect: default;
            species bus_stop aspect: default;
            
            overlay position: {10, 10} size: {400 #px, 200 #px} background: #white transparency: 0.9 border: #black {
                draw "=== ALGORITHME ROBUSTE FIXED ===" at: {10#px, 20#px} color: #black font: font("Arial", 12, #bold);
                
                draw "Routes : " + length(bus_route) at: {20#px, 45#px} color: #blue;
                draw "Arrêts : " + length(bus_stop) at: {20#px, 65#px} color: #red;
                
                if world.successful_conversions > 0 {
                    draw "Trips réussis : " + world.successful_conversions at: {20#px, 85#px} color: #green;
                    if (world.total_trips_found + world.failed_trips) > 0 {
                        draw "Taux succès : " + int((world.total_trips_found/(world.total_trips_found + world.failed_trips)) * 100) + "%" at: {20#px, 105#px} color: #green;
                    }
                    draw "STATUS: OPÉRATIONNEL" at: {20#px, 125#px} color: #green font: font("Arial", 10, #bold);
                    draw "APIs complètes disponibles" at: {20#px, 145#px} color: #gray size: 8;
                } else {
                    draw "STATUS: ÉCHEC TOTAL" at: {20#px, 85#px} color: #red;
                    draw "Trips trouvés : " + world.total_trips_found at: {20#px, 105#px} color: #orange;
                    draw "Trips échoués : " + world.failed_trips at: {20#px, 125#px} color: #red;
                    draw "Vérifiez structure JSON" at: {20#px, 145#px} color: #red;
                }
            }
        }
    }
}