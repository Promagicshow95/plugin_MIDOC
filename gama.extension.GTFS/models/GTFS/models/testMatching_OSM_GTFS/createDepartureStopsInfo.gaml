/**
 * Name: createDepartureStopsInfo_Separated_Format
 * Author: tiend (modifié - Nouveau format JSON séparé)
 * Tags: export, departureStopsInfo, JSON, GTFS, separated, optimized
 * Description: Export departureStopsInfo avec NOUVEAU FORMAT SÉPARÉ
 *              Format: trip_to_stop_ids et trip_to_departure_times (dictionnaires parallèles)
 */

model createDepartureStopsInfo_Separated_Format

global {
    gtfs_file gtfs_f <- gtfs_file("../../includes/hanoi_gtfs_pm");
    shape_file boundary_shp <- shape_file("../../includes/shapeFileHanoishp.shp");
    geometry shape <- envelope(boundary_shp);
    
    string export_folder <- "../../results/stopReseau/";
    
    int total_stops <- 0;
    int departure_stops_count <- 0;
    
    // Parametres d'optimisation
    int min_trips_threshold <- 1;
    int max_stops_per_trip <- 100;
    
    // Debug parameters
    bool debug_mode <- true;
    bool validate_json_format <- true;

    init {
        write "=== CREATION AGENTS BUS_STOP + EXPORT JSON FORMAT SEPARE ===";
        
        create bus_stop from: gtfs_f;
        
        total_stops <- length(bus_stop);
        write "Agents bus_stop crees depuis GTFS : " + total_stops;
        
        list<bus_stop> non_bus_stops <- bus_stop where (each.routeType != 3);
        if !empty(non_bus_stops) {
            ask non_bus_stops {
                do die;
            }
            total_stops <- length(bus_stop);
            write "Filtrage : " + total_stops + " arrets de bus conserves";
        }
        
        departure_stops_count <- length(bus_stop where (each.departureStopsInfo != nil and !empty(each.departureStopsInfo)));
        write "Arrets de depart detectes : " + departure_stops_count + "/" + total_stops;
        
        // Debug structure avant export
        if debug_mode {
            do debug_departure_structure;
        }
        
        // Export nouveau format separe
        do export_departure_stops_separated_format;
        
        // Validation post-export
        if validate_json_format {
            do validate_exported_separated_json;
        }
        
        do display_final_stats;
    }
    
    // EXPORT NOUVEAU FORMAT SEPARE - DICTIONNAIRES PARALLELES
    action export_departure_stops_separated_format {
        write "\n=== EXPORT FORMAT SEPARE (DICTIONNAIRES PARALLELES) ===";
        
        string json_path <- export_folder + "departure_stops_separated.json";
        
        try {
            // Structures pour collecter les donnees par trip
            map<string, list<string>> trip_to_stop_ids <- map<string, list<string>>([]);
            map<string, list<int>> trip_to_departure_times <- map<string, list<int>>([]);
            
            int total_trips_processed <- 0;
            int total_stops_processed <- 0;
            
            // Collecte des donnees depuis tous les arrets de depart
            ask bus_stop where (each.departureStopsInfo != nil and !empty(each.departureStopsInfo)) {
                
                loop trip_id over: departureStopsInfo.keys {
                    // Si ce trip n'a pas encore ete traite
                    if !(trip_to_stop_ids contains_key trip_id) {
                        list<pair<bus_stop, string>> stop_time_pairs <- departureStopsInfo[trip_id];
                        
                        list<string> stop_ids_for_trip <- [];
                        list<int> times_for_trip <- [];
                        
                        // Traitement ordonne des paires (stop, time)
                        loop stop_time_pair over: stop_time_pairs {
                            bus_stop stop_agent <- stop_time_pair.key;
                            string departure_time_str <- stop_time_pair.value;
                            
                            string stop_id_in_trip <- stop_agent.stopId;
                            int departure_time_int <- 0;
                            
                            // Conversion temps en secondes inline
                            if departure_time_str != nil and departure_time_str != "" {
                                try {
                                    departure_time_int <- int(departure_time_str);
                                } catch {
                                    if departure_time_str contains ":" {
                                        list<string> parts <- departure_time_str split_with ":";
                                        if length(parts) >= 2 {
                                            try {
                                                int hours <- int(parts[0]);
                                                int minutes <- int(parts[1]);
                                                int seconds <- length(parts) >= 3 ? int(parts[2]) : 0;
                                                departure_time_int <- hours * 3600 + minutes * 60 + seconds;
                                            } catch {
                                                departure_time_int <- 0;
                                            }
                                        }
                                    } else {
                                        try {
                                            float time_float <- float(departure_time_str);
                                            departure_time_int <- int(time_float);
                                        } catch {
                                            departure_time_int <- 0;
                                        }
                                    }
                                }
                            }
                            
                            if stop_id_in_trip != "" and departure_time_int > 0 {
                                stop_ids_for_trip <+ stop_id_in_trip;
                                times_for_trip <+ departure_time_int;
                                total_stops_processed <- total_stops_processed + 1;
                            }
                        }
                        
                        // Stocker seulement si le trip a des donnees valides
                        if !empty(stop_ids_for_trip) and length(stop_ids_for_trip) = length(times_for_trip) {
                            trip_to_stop_ids[trip_id] <- stop_ids_for_trip;
                            trip_to_departure_times[trip_id] <- times_for_trip;
                            total_trips_processed <- total_trips_processed + 1;
                        }
                    }
                }
            }
            
            write "Donnees collectees :";
            write "  - Trips uniques : " + total_trips_processed;
            write "  - Stops totaux : " + total_stops_processed;
            
            // Debug pour le premier trip
            if debug_mode and !empty(trip_to_stop_ids.keys) {
                string sample_trip <- first(trip_to_stop_ids.keys);
                list<string> sample_stops <- trip_to_stop_ids[sample_trip];
                list<int> sample_times <- trip_to_departure_times[sample_trip];
                
                write "Exemple trip : " + sample_trip;
                write "  Stops : " + length(sample_stops);
                write "  Times : " + length(sample_times);
                write "  Alignement OK : " + (length(sample_stops) = length(sample_times));
                
                int max_display <- min(3, length(sample_stops));
                loop i from: 0 to: (max_display - 1) {
                    write "    " + i + " : " + sample_stops[i] + " -> " + sample_times[i] + "s";
                }
            }
            
            // Construction JSON avec nouveau format
            string json_content <- "{";
            
            // 1. trip_to_stop_ids
            json_content <- json_content + "\"trip_to_stop_ids\":{";
            bool first_trip_stops <- true;
            
            loop trip_id over: trip_to_stop_ids.keys {
                if !first_trip_stops { 
                    json_content <- json_content + ",";
                }
                first_trip_stops <- false;
                
                json_content <- json_content + "\"" + trip_id + "\":[";
                
                list<string> stops_list <- trip_to_stop_ids[trip_id];
                bool first_stop <- true;
                
                loop stop_id over: stops_list {
                    if !first_stop { 
                        json_content <- json_content + ",";
                    }
                    first_stop <- false;
                    json_content <- json_content + "\"" + stop_id + "\"";
                }
                
                json_content <- json_content + "]";
            }
            
            json_content <- json_content + "},";
            
            // 2. trip_to_departure_times
            json_content <- json_content + "\"trip_to_departure_times\":{";
            bool first_trip_times <- true;
            
            loop trip_id over: trip_to_departure_times.keys {
                if !first_trip_times { 
                    json_content <- json_content + ",";
                }
                first_trip_times <- false;
                
                json_content <- json_content + "\"" + trip_id + "\":[";
                
                list<int> times_list <- trip_to_departure_times[trip_id];
                bool first_time <- true;
                
                loop time_int over: times_list {
                    if !first_time { 
                        json_content <- json_content + ",";
                    }
                    first_time <- false;
                    json_content <- json_content + string(time_int);
                }
                
                json_content <- json_content + "]";
            }
            
            json_content <- json_content + "}";
            json_content <- json_content + "}";
            
            // Sauvegarde
            save json_content to: json_path format: "text";
            
            write "EXPORT FORMAT SEPARE REUSSI : " + json_path;
            write "   Trips exportes : " + total_trips_processed;
            write "   Stops totaux : " + total_stops_processed;
            
            // Debug: Afficher un extrait du JSON genere
            if debug_mode {
                string json_sample <- length(json_content) > 800 ? copy(json_content, 0, 800) + "..." : json_content;
                write "Extrait JSON genere :\n" + json_sample;
            }
            
        } catch {
            write "ERREUR export format separe";
        }
    }
    
    // VALIDATION DU JSON SEPARE EXPORTE
    action validate_exported_separated_json {
        write "\n=== VALIDATION JSON FORMAT SEPARE ===";
        
        string json_path <- export_folder + "departure_stops_separated.json";
        
        try {
            file json_f <- text_file(json_path);
            string content <- string(json_f);
            
            write "Taille fichier : " + length(content) + " caracteres";
            
            // Test de parsing
            try {
                map<string, unknown> parsed <- from_json(content);
                write "JSON parsing reussi";
                
                if (parsed contains_key "trip_to_stop_ids") and (parsed contains_key "trip_to_departure_times") {
                    map<string, unknown> trip_stops <- map<string, unknown>(parsed["trip_to_stop_ids"]);
                    map<string, unknown> trip_times <- map<string, unknown>(parsed["trip_to_departure_times"]);
                    
                    write "Structure attendue : trip_to_stop_ids (" + length(trip_stops) + " trips)";
                    write "Structure attendue : trip_to_departure_times (" + length(trip_times) + " trips)";
                    
                    // Verification de l'alignement
                    if length(trip_stops) = length(trip_times) {
                        write "Nombre de trips aligne entre les deux dictionnaires";
                        
                        // Test sur un trip echantillon
                        if !empty(trip_stops.keys) {
                            string sample_trip <- first(trip_stops.keys);
                            
                            if trip_times contains_key sample_trip {
                                try {
                                    list<string> stops_array <- list<string>(trip_stops[sample_trip]);
                                    list<int> times_array <- list<int>(trip_times[sample_trip]);
                                    
                                    write "Trip echantillon : " + sample_trip;
                                    write "  Stops : " + length(stops_array);
                                    write "  Times : " + length(times_array);
                                    
                                    if length(stops_array) = length(times_array) {
                                        write "ALIGNEMENT PARFAIT pour " + sample_trip;
                                        
                                        if length(stops_array) > 0 {
                                            write "  Premier element : " + stops_array[0] + " -> " + times_array[0] + "s";
                                        }
                                        
                                        write "FORMAT SEPARE VALIDE ET ALIGNE";
                                    } else {
                                        write "DESALIGNEMENT pour " + sample_trip + " : " + length(stops_array) + " vs " + length(times_array);
                                    }
                                    
                                } catch {
                                    write "Erreur conversion arrays pour " + sample_trip;
                                }
                            } else {
                                write "Trip " + sample_trip + " manquant dans trip_to_departure_times";
                            }
                        }
                    } else {
                        write "DESALIGNEMENT GLOBAL : " + length(trip_stops) + " trips stops vs " + length(trip_times) + " trips times";
                    }
                    
                } else {
                    write "Cles manquantes : trip_to_stop_ids ou trip_to_departure_times";
                }
                
            } catch {
                write "JSON invalide ou non parsable";
            }
            
        } catch {
            write "Impossible de lire le fichier exporte";
        }
    }
    
    // CONVERSION TEMPS EN SECONDES
    int parse_time_to_seconds(string time_str) {
        if time_str = nil or time_str = "" {
            return 0;
        }
        
        try {
            // Essai direct en entier
            int direct_int <- int(time_str);
            return direct_int;
        } catch {
            // Essai format HH:MM:SS
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
            
            // Essai float puis conversion
            try {
                float time_float <- float(time_str);
                return int(time_float);
            } catch {
                return 0;
            }
        }
    }
    
    action display_final_stats {
        write "\n=== STATISTIQUES FINALES ===";
        write "Total arrets crees : " + total_stops;
        write "Arrets de depart : " + departure_stops_count;
        
        if total_stops > 0 {
            float departure_rate <- (departure_stops_count / total_stops) * 100.0;
            write "Taux arrets de depart : " + int(departure_rate) + "%";
        }
        
        if departure_stops_count > 0 {
            int total_trips <- 0;
            int total_stop_pairs <- 0;
            
            ask bus_stop where (each.departureStopsInfo != nil and !empty(each.departureStopsInfo)) {
                total_trips <- total_trips + length(departureStopsInfo);
                
                loop trip_pairs over: departureStopsInfo.values {
                    total_stop_pairs <- total_stop_pairs + length(trip_pairs);
                }
            }
            
            write "Total trips : " + total_trips;
            write "Total paires (stop, time) : " + total_stop_pairs;
            if total_trips > 0 {
                write "Moyenne stops/trip : " + (total_stop_pairs / total_trips);
            }
        }
        
        write "\nNOUVEAU FORMAT JSON SEPARE";
        write "Structure: {trip_to_stop_ids: {...}, trip_to_departure_times: {...}}";
        write "Dictionnaires paralleles indexes par tripId";
        write "Compatible avec zip() pour reconstruction paires";
    }
    
    action debug_departure_structure {
        write "\n=== DEBUG STRUCTURE DEPARTUREINFO ===";
        
        bus_stop sample <- first(bus_stop where (each.departureStopsInfo != nil and !empty(each.departureStopsInfo)));
        if sample = nil {
            write "Aucun arret de depart trouve";
            return;
        }
        
        write "Arret echantillon : " + sample.stopId;
        write "Nombre de trips : " + length(sample.departureStopsInfo);
        
        if !empty(sample.departureStopsInfo.keys) {
            string first_trip_id <- first(sample.departureStopsInfo.keys);
            list<pair<bus_stop, string>> first_trip_pairs <- sample.departureStopsInfo[first_trip_id];
            
            write "Premier trip : " + first_trip_id;
            write "Paires (stop, time) : " + length(first_trip_pairs);
            
            int max_display <- min(3, length(first_trip_pairs));
            loop i from: 0 to: (max_display - 1) {
                pair<bus_stop, string> pair_i <- first_trip_pairs[i];
                bus_stop stop_agent <- pair_i.key;
                string departure_time <- pair_i.value;
                write "  " + i + " : " + stop_agent.stopId + " -> " + departure_time;
            }
            
            if length(first_trip_pairs) > 3 {
                write "  ... et " + (length(first_trip_pairs) - 3) + " autres paires";
            }
        }
        
        write "Structure en memoire OK - Prete pour export format separe";
    }
    
    // ACTION DE TEST AVEC JSON SEPARE EN DUR
    action test_with_separated_hardcoded_json {
        write "\n=== TEST AVEC JSON FORMAT SEPARE EN DUR ===";
        
        // JSON correct format separe directement dans le code
        string test_json_content <- "{\"trip_to_stop_ids\":{\"trip_1\":[\"S1\",\"S2\",\"S3\"],\"trip_2\":[\"S5\",\"S8\"]},\"trip_to_departure_times\":{\"trip_1\":[3600,3900,4200],\"trip_2\":[7200,7500]}}";
        
        write "JSON test separe en dur :\n" + test_json_content;
        
        try {
            map<string, unknown> json_data <- from_json(test_json_content);
            write "Parsing JSON separe reussi";
            
            // Verification structure
            if (json_data contains_key "trip_to_stop_ids") and (json_data contains_key "trip_to_departure_times") {
                map<string, unknown> trip_stops <- map<string, unknown>(json_data["trip_to_stop_ids"]);
                map<string, unknown> trip_times <- map<string, unknown>(json_data["trip_to_departure_times"]);
                
                write "Structure attendue : trip_to_stop_ids (" + length(trip_stops) + " trips)";
                write "Structure attendue : trip_to_departure_times (" + length(trip_times) + " trips)";
                
                // Test alignement
                if !empty(trip_stops.keys) {
                    string test_trip <- first(trip_stops.keys);
                    
                    if trip_times contains_key test_trip {
                        try {
                            list<string> stops_array <- list<string>(trip_stops[test_trip]);
                            list<int> times_array <- list<int>(trip_times[test_trip]);
                            
                            write "Test trip : " + test_trip;
                            write "  Stops : " + stops_array;
                            write "  Times : " + times_array;
                            
                            if length(stops_array) = length(times_array) {
                                write "ALIGNEMENT PARFAIT - FORMAT SEPARE VALIDE";
                                
                                write "Reconstruction paires :";
                                loop i from: 0 to: (length(stops_array) - 1) {
                                    write "  " + stops_array[i] + " -> " + times_array[i] + "s";
                                }
                            } else {
                                write "Desalignement detecte";
                            }
                            
                        } catch {
                            write "Erreur conversion arrays";
                        }
                    }
                }
            } else {
                write "Cles manquantes dans structure separee";
            }
            
        } catch {
            write "JSON separe invalide ou non parsable";
        }
        
        write "\nCe test valide le nouveau format JSON separe";
        write "Si ce test reussit, le parsing cote modele sera plus simple";
    }
    
    // CREATION D'UN FICHIER JSON TEST SEPARE MINIMAL
    action create_minimal_separated_test_json {
        write "\n=== CREATION FICHIER JSON TEST SEPARE MINIMAL ===";
        
        string test_json_path <- export_folder + "test_separated_minimal.json";
        
        // JSON test avec format separe minimal
        string test_content <- "{";
        test_content <- test_content + "\"trip_to_stop_ids\":{";
        test_content <- test_content + "\"test_trip_1\":[\"STOP_A\",\"STOP_B\",\"STOP_C\"],";
        test_content <- test_content + "\"test_trip_2\":[\"STOP_X\",\"STOP_Y\"]";
        test_content <- test_content + "},";
        test_content <- test_content + "\"trip_to_departure_times\":{";
        test_content <- test_content + "\"test_trip_1\":[3600,4200,4800],";
        test_content <- test_content + "\"test_trip_2\":[7200,7800]";
        test_content <- test_content + "}";
        test_content <- test_content + "}";
        
        try {
            save test_content to: test_json_path format: "text";
            write "Fichier JSON separe test cree " + test_json_path;
            write "Taille " + length(test_content) + " caracteres";
            
            // Validation immediate
            try {
                map<string, unknown> validation <- from_json(test_content);
                write "Validation reussie - JSON separe test parfaitement forme";
                
                // Test reconstruction
                map<string, unknown> stops_dict <- map<string, unknown>(validation["trip_to_stop_ids"]);
                map<string, unknown> times_dict <- map<string, unknown>(validation["trip_to_departure_times"]);
                
                write "Reconstruction test";
                loop trip_id over: stops_dict.keys {
                    if times_dict contains_key trip_id {
                        list<string> stops <- list<string>(stops_dict[trip_id]);
                        list<int> times <- list<int>(times_dict[trip_id]);
                        
                        write "  " + trip_id + " - " + length(stops) + " stops, " + length(times) + " times";
                        if length(stops) = length(times) {
                            write "    Alignement OK";
                        }
                    }
                }
                
            } catch {
                write "Erreur validation JSON separe test";
            }
            
        } catch {
            write "Erreur creation fichier JSON separe test";
        }
    }
}

species bus_stop skills: [TransportStopSkill] {
    map<string, list<pair<bus_stop, string>>> departureStopsInfo;
    
    aspect base {
        rgb stop_color;
        
        if departureStopsInfo != nil and !empty(departureStopsInfo) {
            stop_color <- #green;
        } else {
            stop_color <- #blue;
        }
        
        draw circle(100.0) at: location color: stop_color;
        
        if departureStopsInfo != nil and !empty(departureStopsInfo) {
            draw string(length(departureStopsInfo)) + " trips" 
                 size: 8 color: #black at: location + {0, -150};
        }
    }
    
    aspect detailed {
        rgb stop_color;
        
        if departureStopsInfo != nil and !empty(departureStopsInfo) {
            stop_color <- #green;
        } else {
            stop_color <- #blue;
        }
        
        draw circle(120.0) at: location color: stop_color;
        
        if stopId != nil {
            draw stopId size: 10 color: #black at: location + {0, 200};
        }
        
        if departureStopsInfo != nil and !empty(departureStopsInfo) {
            int total_stops_in_trips <- 0;
            loop trip_pairs over: departureStopsInfo.values {
                total_stops_in_trips <- total_stops_in_trips + length(trip_pairs);
            }
            draw string(length(departureStopsInfo)) + " trips (" + total_stops_in_trips + " stops)" 
                 size: 8 color: #white at: location;
        }
    }
}

experiment GTFSExperimentSeparated type: gui {
    
    parameter "Seuil min trips" var: min_trips_threshold min: 1 max: 10;
    parameter "Max stops/trip" var: max_stops_per_trip min: 10 max: 200;
    parameter "Mode debug" var: debug_mode;
    parameter "Valider JSON" var: validate_json_format;
    
    action export_separated {
        ask world { do export_departure_stops_separated_format; }
    }
    
    action debug_structure {
        ask world { do debug_departure_structure; }
    }
    
    action validate_separated_json {
        ask world { do validate_exported_separated_json; }
    }
    
    action test_separated_hardcoded {
        ask world { do test_with_separated_hardcoded_json; }
    }
    
    action create_separated_test_json {
        ask world { do create_minimal_separated_test_json; }
    }
    
    user_command "Export Format Separe" action: export_separated;
    user_command "Debug Structure" action: debug_structure;
    user_command "Valider JSON Separe" action: validate_separated_json;
    user_command "Test JSON Separe En Dur" action: test_separated_hardcoded;
    user_command "Creer JSON Separe Test" action: create_separated_test_json;

    output {
        display "Export JSON FORMAT SEPARE" background: #white {
            species bus_stop aspect: detailed;
            
            overlay position: {10, 10} size: {480 #px, 180 #px} background: #white transparency: 0.9 border: #black {
                draw "=== EXPORT JSON FORMAT SEPARE ===" at: {10#px, 20#px} color: #black font: font("Arial", 11, #bold);
                
                draw "Total arrets : " + length(bus_stop) at: {20#px, 40#px} color: #black;
                
                int departure_stops <- length(bus_stop where (each.departureStopsInfo != nil and !empty(each.departureStopsInfo)));
                draw "Arrets depart : " + departure_stops at: {20#px, 60#px} color: #green;
                
                if departure_stops > 0 {
                    int total_trips <- 0;
                    ask bus_stop where (each.departureStopsInfo != nil) {
                        total_trips <- total_trips + length(departureStopsInfo);
                    }
                    draw "Total trips : " + total_trips at: {20#px, 80#px} color: #purple;
                }
                
                draw "NOUVEAU FORMAT SEPARE" at: {20#px, 105#px} color: #green size: 9;
                draw "trip_to_stop_ids + trip_to_departure_times" at: {20#px, 125#px} color: #green size: 9;
                draw "Dictionnaires paralleles indexes par tripId" at: {20#px, 145#px} color: #black size: 8;
                draw "Compatible zip() - parsing plus simple" at: {20#px, 165#px} color: #black size: 8;
            }
        }
    }
}