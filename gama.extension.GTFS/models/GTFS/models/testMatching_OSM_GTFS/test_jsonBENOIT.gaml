model TestJSON

global {
    string results_folder <- "../../results/";
    string stops_folder <- "../../results/stopReseau/";

    // Structure principale : stop_id -> trip_id -> liste de paires (stop_id, temps)
    map<string, map<string, list<pair<string, int>>>> stop_to_all_trips;
    
    // Structure finale : trip_id -> liste de paires (stop_id, temps) 
    map<string, list<pair<string, int>>> trip_to_schedule;
    
    // Statistiques
    int total_stops_processed <- 0;
    int total_trips_found <- 0;
    int parsing_errors <- 0;

    init {
        do pre_read_and_parse_json;
        do build_trip_map;
        do display_results;
    }

    // PRÉ-LECTURE & PARSE JSON COMPLET
    action pre_read_and_parse_json {
        write "=== PARSING JSON COMPLET ===";
        
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
            
            // Traiter chaque arrêt
            loop stop_data over: stops_list {
                do process_stop(stop_data);
            }
            
        } catch {
            write "ERREUR: Impossible de lire le fichier JSON";
        }
    }
    
    // TRAITEMENT D'UN ARRÊT
    action process_stop(map<string, unknown> stop_data) {
        try {
            string stop_id <- string(stop_data["stopId"]);
            
            // Vérifier si c'est un arrêt de bus
            bool is_bus <- true;
            if stop_data contains_key "routeType" {
                int route_type <- int(stop_data["routeType"]);
                is_bus <- (route_type = 3);
            }
            
            if stop_id != nil and stop_id != "" and is_bus and 
               stop_data contains_key "departureStopsInfo" {
                
                total_stops_processed <- total_stops_processed + 1;
                
                // Initialiser la map pour cet arrêt
                if !(stop_to_all_trips contains_key stop_id) {
                    stop_to_all_trips[stop_id] <- map<string, list<pair<string, int>>>([]);
                }
                
                // Traiter les trips de cet arrêt
                map<string, unknown> departure_info <- map<string, unknown>(stop_data["departureStopsInfo"]);
                do process_trips_for_stop(stop_id, departure_info);
            }
            
        } catch {
            parsing_errors <- parsing_errors + 1;
        }
    }
    
    // TRAITEMENT DES TRIPS D'UN ARRÊT
    action process_trips_for_stop(string stop_id, map<string, unknown> departure_info) {
        loop trip_id over: departure_info.keys {
            try {
                unknown trip_data <- departure_info[trip_id];
                list<pair<string, int>> schedule <- parse_trip_schedule(trip_data, trip_id);
                
                if !empty(schedule) {
                    stop_to_all_trips[stop_id][trip_id] <- schedule;
                    total_trips_found <- total_trips_found + 1;
                }
                
            } catch {
                parsing_errors <- parsing_errors + 1;
            }
        }
    }
    
    // PARSING D'UN SCHEDULE DE TRIP
    list<pair<string, int>> parse_trip_schedule(unknown trip_data, string trip_id) {
        list<pair<string, int>> result <- [];
        
        try {
            // Cas 1: Tableau de paires [stopId, time]
            list<unknown> trip_array <- list<unknown>(trip_data);
            
            loop pair_element over: trip_array {
                try {
                    list<unknown> pair_data <- list<unknown>(pair_element);
                    
                    if length(pair_data) >= 2 {
                        string stop_id <- string(pair_data[0]);
                        string time_str <- string(pair_data[1]);
                        int time_seconds <- convert_time_to_seconds(time_str);
                        
                        if stop_id != nil and stop_id != "" and time_seconds > 0 {
                            result <+ pair(stop_id, time_seconds);
                        }
                    }
                } catch {
                    // Paire invalide, continuer
                }
            }
            
        } catch {
            // Cas 2: String JSON encodé
            try {
                string trip_str <- string(trip_data);
                unknown parsed_data <- from_json(trip_str);
                list<unknown> trip_array <- list<unknown>(parsed_data);
                
                loop pair_element over: trip_array {
                    try {
                        list<unknown> pair_data <- list<unknown>(pair_element);
                        
                        if length(pair_data) >= 2 {
                            string stop_id <- string(pair_data[0]);
                            string time_str <- string(pair_data[1]);
                            int time_seconds <- convert_time_to_seconds(time_str);
                            
                            if stop_id != nil and stop_id != "" and time_seconds > 0 {
                                result <+ pair(stop_id, time_seconds);
                            }
                        }
                    } catch {
                        // Continue
                    }
                }
            } catch {
                // Parsing complètement échoué
            }
        }
        
        return result;
    }
    
    // CONVERSION TEMPS EN SECONDES
    int convert_time_to_seconds(string time_str) {
        if time_str = nil or time_str = "" {
            return 0;
        }
        
        try {
            // Déjà en secondes
            int direct_seconds <- int(time_str);
            return direct_seconds;
        } catch {
            try {
                // Format HH:MM:SS ou HH:MM
                if time_str contains ":" {
                    list<string> parts <- time_str split_with ":";
                    if length(parts) >= 2 {
                        int hours <- int(parts[0]);
                        int minutes <- int(parts[1]);
                        int seconds <- length(parts) >= 3 ? int(parts[2]) : 0;
                        
                        return hours * 3600 + minutes * 60 + seconds;
                    }
                }
                
                // Float
                float time_float <- float(time_str);
                return int(time_float);
            } catch {
                return 0;
            }
        }
    }
    
    // CONSTRUCTION MAP FINALE DES TRIPS
    action build_trip_map {
        write "\n=== CONSTRUCTION MAP TRIPS ===";
        
        trip_to_schedule <- map<string, list<pair<string, int>>>([]);
        
        // Parcourir tous les stops et leurs trips
        loop stop_id over: stop_to_all_trips.keys {
            map<string, list<pair<string, int>>> trips_from_stop <- stop_to_all_trips[stop_id];
            
            loop trip_id over: trips_from_stop.keys {
                // Éviter les doublons (même trip depuis plusieurs stops)
                if !(trip_to_schedule contains_key trip_id) {
                    trip_to_schedule[trip_id] <- trips_from_stop[trip_id];
                }
            }
        }
        
        write "Map finale construite : " + length(trip_to_schedule) + " trips uniques";
    }
    
    // AFFICHAGE RÉSULTATS
    action display_results {
        write "\n=== RÉSULTATS PARSING ===";
        write "Arrêts traités : " + total_stops_processed;
        write "Trips trouvés : " + total_trips_found;
        write "Trips uniques : " + length(trip_to_schedule);
        write "Erreurs parsing : " + parsing_errors;
        
        if parsing_errors > 0 {
            write "Taux d'erreur : " + int((parsing_errors / total_trips_found) * 100) + "%";
        }
        
        // Exemple de trip
        if !empty(trip_to_schedule) {
            string sample_trip <- first(trip_to_schedule.keys);
            list<pair<string, int>> sample_schedule <- trip_to_schedule[sample_trip];
            
            write "\nExemple - Trip : " + sample_trip;
            write "Nombre d'arrêts : " + length(sample_schedule);
            
            if length(sample_schedule) > 0 {
                write "Séquence (3 premiers) :";
                int max_display <- min(3, length(sample_schedule));
                loop i from: 0 to: (max_display - 1) {
                    pair<string, int> stop_time <- sample_schedule[i];
                    write "  " + stop_time.key + " à " + stop_time.value + "s";
                }
            }
        }
    }
    
    // APIS D'ACCÈS
    list<pair<string, int>> get_trip_schedule(string trip_id) {
        if trip_to_schedule contains_key trip_id {
            return trip_to_schedule[trip_id];
        }
        return [];
    }
    
    list<string> get_all_trip_ids {
        return trip_to_schedule.keys;
    }
    
    int get_trip_count {
        return length(trip_to_schedule);
    }
    
    list<string> get_stops_for_trip(string trip_id) {
        if trip_to_schedule contains_key trip_id {
            list<pair<string, int>> schedule <- trip_to_schedule[trip_id];
            return schedule collect (each.key);
        }
        return [];
    }
    
    int get_departure_time(string trip_id, string stop_id) {
        if trip_to_schedule contains_key trip_id {
            list<pair<string, int>> schedule <- trip_to_schedule[trip_id];
            loop stop_time over: schedule {
                if stop_time.key = stop_id {
                    return stop_time.value;
                }
            }
        }
        return -1;
    }
}

experiment test_json type: gui {
    
    action test_api {
        ask world {
            write "\n=== TEST APIS ===";
            write "Nombre total trips : " + get_trip_count();
            
            if get_trip_count() > 0 {
                list<string> all_trips <- get_all_trip_ids();
                string test_trip <- all_trips[0];
                
                write "Test trip : " + test_trip;
                list<string> stops <- get_stops_for_trip(test_trip);
                write "Arrêts : " + length(stops);
                
                if length(stops) > 0 {
                    string first_stop <- stops[0];
                    int departure <- get_departure_time(test_trip, first_stop);
                    write "Départ de " + first_stop + " : " + departure + "s";
                }
            }
        }
    }
    
    user_command "Test APIs" action: test_api;
    
    output {
        display "Parsing JSON" background: #white {
            overlay position: {10, 10} size: {300 #px, 150 #px} background: #white transparency: 0.8 {
                draw "=== PARSING JSON ===" at: {10#px, 20#px} color: #black font: font("Arial", 12, #bold);
                draw "Arrêts traités : " + world.total_stops_processed at: {20#px, 40#px} color: #blue;
                draw "Trips trouvés : " + world.total_trips_found at: {20#px, 60#px} color: #green;
                draw "Trips uniques : " + length(world.trip_to_schedule) at: {20#px, 80#px} color: #purple;
                draw "Erreurs : " + world.parsing_errors at: {20#px, 100#px} color: #red;
                
                if length(world.trip_to_schedule) > 0 {
                    draw "STATUS: SUCCÈS" at: {20#px, 120#px} color: #green;
                } else {
                    draw "STATUS: ÉCHEC" at: {20#px, 120#px} color: #red;
                }
            }
        }
    }
}