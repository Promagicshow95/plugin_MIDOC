/**
 * Name: createDepartureStopsInfo_Optimized_Fixed
 * Author: tiend (modifié - Fix double encodage JSON)
 * Tags: export, departureStopsInfo, JSON, GTFS, optimized, fixed
 * Description: Export departureStopsInfo CORRIGÉ pour générer de vrais tableaux JSON
 *              Fix: Assure que departureStopsInfo[tripId] = [...] et non "..."
 */

model createDepartureStopsInfo_Optimized_Fixed

global {
    gtfs_file gtfs_f <- gtfs_file("../../includes/hanoi_gtfs_pm");
    shape_file boundary_shp <- shape_file("../../includes/shapeFileHanoishp.shp");
    geometry shape <- envelope(boundary_shp);
    
    string export_folder <- "../../results/stopReseau/";
    
    int total_stops <- 0;
    int departure_stops_count <- 0;
    
    // Paramètres d'optimisation
    int min_trips_threshold <- 1;
    int max_stops_per_trip <- 100;
    bool compact_format <- true;
    
    // Debug parameters
    bool debug_mode <- true;
    bool validate_json_format <- true;

    init {
        write "=== CRÉATION AGENTS BUS_STOP + EXPORT JSON CORRIGÉ ===";
        
        create bus_stop from: gtfs_f;
        
        total_stops <- length(bus_stop);
        write "Agents bus_stop créés depuis GTFS : " + total_stops;
        
        list<bus_stop> non_bus_stops <- bus_stop where (each.routeType != 3);
        if !empty(non_bus_stops) {
            ask non_bus_stops {
                do die;
            }
            total_stops <- length(bus_stop);
            write "Filtrage : " + total_stops + " arrêts de bus conservés";
        }
        
        departure_stops_count <- length(bus_stop where (each.departureStopsInfo != nil and !empty(each.departureStopsInfo)));
        write "Arrêts de départ détectés : " + departure_stops_count + "/" + total_stops;
        
        // Debug structure avant export
        if debug_mode {
            do debug_departure_structure;
        }
        
        // Export format compact corrigé
        do export_departure_stops_compact_fixed;
        
        // Validation post-export
        if validate_json_format {
            do validate_exported_json;
        }
        
        do display_final_stats;
    }
    
    // EXPORT COMPACT CORRIGÉ - GÉNÈRE VRAIS TABLEAUX JSON
    action export_departure_stops_compact_fixed {
        write "\n=== EXPORT COMPACT CORRIGÉ (VRAIS TABLEAUX JSON) ===";
        
        string json_path <- export_folder + "departure_stops_info_stopid.json";
        
        try {
            string json_content <- "{\"departure_stops_info\":[";
            bool first_stop <- true;
            int exported_stops <- 0;
            int total_trips_exported <- 0;
            int total_pairs_exported <- 0;
            
            ask bus_stop where (each.departureStopsInfo != nil and !empty(each.departureStopsInfo)) {
                if !first_stop { 
                    json_content <- json_content + ",";
                }
                first_stop <- false;
                exported_stops <- exported_stops + 1;
                
                // Debug pour le premier stop
                if debug_mode and exported_stops = 1 {
                    write "DEBUG - Premier stop : " + stopId;
                    write "  Nombre de trips : " + length(departureStopsInfo);
                }
                
                // Début du stop
                json_content <- json_content + "{";
                json_content <- json_content + "\"stopId\":\"" + stopId + "\",";
                json_content <- json_content + "\"location\":[" + int(location.x) + "," + int(location.y) + "],";
                json_content <- json_content + "\"routeType\":" + routeType + ",";
                json_content <- json_content + "\"departureStopsInfo\":{";
                
                // Traitement des trips
                bool first_trip <- true;
                loop trip_id over: departureStopsInfo.keys {
                    if !first_trip { 
                        json_content <- json_content + ",";
                    }
                    first_trip <- false;
                    total_trips_exported <- total_trips_exported + 1;
                    
                    // CRITIQUE: Début du tableau pour ce trip
                    json_content <- json_content + "\"" + trip_id + "\":[";
                    
                    list<pair<bus_stop, string>> stop_time_pairs <- departureStopsInfo[trip_id];
                    bool first_pair <- true;
                    
                    // Debug pour le premier trip du premier stop
                    if debug_mode and exported_stops = 1 and total_trips_exported = 1 {
                        write "  DEBUG - Premier trip : " + trip_id;
                        write "    Nombre de paires : " + length(stop_time_pairs);
                    }
                    
                    // Traitement des paires (stop, time)
                    loop stop_time_pair over: stop_time_pairs {
                        if !first_pair { 
                            json_content <- json_content + ",";
                        }
                        first_pair <- false;
                        total_pairs_exported <- total_pairs_exported + 1;
                        
                        bus_stop stop_agent <- stop_time_pair.key;
                        string departure_time <- stop_time_pair.value;
                        string stop_id_in_trip <- stop_agent.stopId;
                        
                        // CRITIQUE: Chaque paire est un tableau [stopId, time]
                        json_content <- json_content + "[\"" + stop_id_in_trip + "\",\"" + departure_time + "\"]";
                        
                        // Debug pour les 3 premières paires du premier trip
                        if debug_mode and exported_stops = 1 and total_trips_exported = 1 and total_pairs_exported <= 3 {
                            write "    Paire " + total_pairs_exported + " : [\"" + stop_id_in_trip + "\",\"" + departure_time + "\"]";
                        }
                    }
                    
                    // CRITIQUE: Fin du tableau pour ce trip
                    json_content <- json_content + "]";
                }
                
                // Fin du stop
                json_content <- json_content + "}}";
            }
            
            // Fermeture du JSON
            json_content <- json_content + "]}";
            
            // Sauvegarde avec validation
            save json_content to: json_path format: "text";
            
            write "✅ EXPORT COMPACT CORRIGÉ RÉUSSI : " + json_path;
            write "   Arrêts exportés : " + exported_stops;
            write "   Trips exportés : " + total_trips_exported;
            write "   Paires (stop,time) exportées : " + total_pairs_exported;
            
            // Debug: Afficher un extrait du JSON généré
            if debug_mode {
                string json_sample <- length(json_content) > 500 ? copy(json_content, 0, 500) + "..." : json_content;
                write "📋 Extrait JSON généré :\n" + json_sample;
            }
            
        } catch {
            write "❌ ERREUR export compact corrigé";
        }
    }
    
    // VALIDATION DU JSON EXPORTÉ
    action validate_exported_json {
        write "\n=== VALIDATION JSON EXPORTÉ ===";
        
        string json_path <- export_folder + "departure_stops_info_stopid.json";
        
        try {
            file json_f <- text_file(json_path);
            string content <- string(json_f);
            
            write "📏 Taille fichier : " + length(content) + " caractères";
            
            // Test de parsing
            try {
                map<string, unknown> parsed <- from_json(content);
                write "✅ JSON parsing réussi";
                
                if parsed contains_key "departure_stops_info" {
                    list<map<string, unknown>> stops_list <- list<map<string, unknown>>(parsed["departure_stops_info"]);
                    write "✅ Structure attendue : " + length(stops_list) + " stops";
                    
                    if length(stops_list) > 0 {
                        map<string, unknown> first_stop <- stops_list[0];
                        write "✅ Premier stop keys : " + first_stop.keys;
                        
                        if first_stop contains_key "departureStopsInfo" {
                            map<string, unknown> dep_info <- map<string, unknown>(first_stop["departureStopsInfo"]);
                            write "✅ departureStopsInfo avec " + length(dep_info) + " trips";
                            
                            if !empty(dep_info.keys) {
                                string first_trip <- first(dep_info.keys);
                                unknown trip_data <- dep_info[first_trip];
                                
                                // TEST CRITIQUE: Vérifier que trip_data est une liste, pas une chaîne
                                try {
                                    list<unknown> trip_array <- list<unknown>(trip_data);
                                    write "✅ Trip " + first_trip + " est un TABLEAU avec " + length(trip_array) + " éléments";
                                    
                                    if length(trip_array) > 0 {
                                        unknown first_element <- trip_array[0];
                                        try {
                                            list<string> pair_data <- list<string>(first_element);
                                            if length(pair_data) = 2 {
                                                write "✅ Premier élément est une paire valide : [" + pair_data[0] + ", " + pair_data[1] + "]";
                                            } else {
                                                write "⚠️ Premier élément n'a pas 2 éléments : " + length(pair_data);
                                            }
                                        } catch {
                                            write "❌ Premier élément n'est pas convertible en list<string>";
                                        }
                                    }
                                } catch {
                                    write "❌ PROBLÈME : Trip " + first_trip + " n'est PAS un tableau !";
                                    write "    Type détecté : " + string(trip_data);
                                    write "    CAUSE : Double encodage JSON détecté";
                                }
                            }
                        }
                    }
                }
                
            } catch {
                write "❌ JSON invalide ou non parsable";
            }
            
        } catch {
            write "❌ Impossible de lire le fichier exporté";
        }
    }
    
    // Export ultra-léger corrigé
    action export_departure_stops_light_fixed {
        write "\n=== EXPORT ULTRA-LÉGER CORRIGÉ ===";
        
        string json_path <- export_folder + "departure_stops_info_stopid.json";
        
        try {
            string json_content <- "{\"departure_stops_info\":[";
            bool first_stop <- true;
            int exported_stops <- 0;
            int skipped_stops <- 0;
            
            ask bus_stop where (each.departureStopsInfo != nil and !empty(each.departureStopsInfo)) {
                if length(departureStopsInfo) < min_trips_threshold {
                    skipped_stops <- skipped_stops + 1;
                } else {
                    if !first_stop { 
                        json_content <- json_content + ","; 
                    }
                    first_stop <- false;
                    exported_stops <- exported_stops + 1;
                    
                    json_content <- json_content + "{\"s\":\"" + stopId + "\",\"d\":{";
                    
                    bool first_trip <- true;
                    loop trip_id over: departureStopsInfo.keys {
                        if !first_trip { 
                            json_content <- json_content + ","; 
                        }
                        first_trip <- false;
                        
                        // CRITIQUE: Début tableau pour ce trip
                        json_content <- json_content + "\"" + trip_id + "\":[";
                        
                        list<pair<bus_stop, string>> pairs <- departureStopsInfo[trip_id];
                        bool first_pair <- true;
                        
                        int stops_to_export <- min(length(pairs), max_stops_per_trip);
                        
                        loop i from: 0 to: (stops_to_export - 1) {
                            pair<bus_stop, string> pair_i <- pairs[i];
                            if !first_pair { 
                                json_content <- json_content + ","; 
                            }
                            first_pair <- false;
                            
                            bus_stop stop_agent <- pair_i.key;
                            string departure_time <- pair_i.value;
                            
                            // CRITIQUE: Chaque paire est un tableau
                            json_content <- json_content + "[\"" + stop_agent.stopId + "\",\"" + departure_time + "\"]";
                        }
                        
                        // CRITIQUE: Fin tableau pour ce trip
                        json_content <- json_content + "]";
                    }
                    
                    json_content <- json_content + "}}";
                }
            }
            
            json_content <- json_content + "]}";
            
            save json_content to: json_path format: "text";
            
            write "✅ EXPORT ULTRA-LÉGER CORRIGÉ RÉUSSI : " + json_path;
            write "   Arrêts exportés : " + exported_stops;
            write "   Arrêts ignorés : " + skipped_stops;
            
        } catch {
            write "❌ Erreur export ultra-léger corrigé";
        }
    }
    
    // Export batch corrigé
    action export_departure_stops_batch_fixed {
        write "\n=== EXPORT PAR BATCH CORRIGÉ ===";
        
        list<bus_stop> departure_stops <- bus_stop where (each.departureStopsInfo != nil and !empty(each.departureStopsInfo));
        int total_departure_stops <- length(departure_stops);
        
        if total_departure_stops = 0 {
            write "Aucun arrêt de départ à exporter";
            return;
        }
        
        int batch_size <- 50;
        int batch_number <- 1;
        int current <- 0;
        
        loop while: (current < total_departure_stops) {
            int end_idx <- min(current + batch_size - 1, total_departure_stops - 1);
            list<bus_stop> batch <- [];
            
            loop i from: current to: end_idx {
                batch <+ departure_stops[i];
            }
            
            string batch_filename <- export_folder + "departure_batch_" + batch_number + "_fixed.json";
            
            try {
                string json_content <- "{\"departure_stops_info\":[";
                bool first_stop <- true;
                
                loop stop over: batch {
                    if !first_stop { 
                        json_content <- json_content + ","; 
                    }
                    first_stop <- false;
                    
                    json_content <- json_content + "{\"stopId\":\"" + stop.stopId + "\",\"departureStopsInfo\":{";
                    
                    bool first_trip <- true;
                    loop trip_id over: stop.departureStopsInfo.keys {
                        if !first_trip { 
                            json_content <- json_content + ","; 
                        }
                        first_trip <- false;
                        
                        // CRITIQUE: Début tableau
                        json_content <- json_content + "\"" + trip_id + "\":[";
                        
                        list<pair<bus_stop, string>> pairs <- stop.departureStopsInfo[trip_id];
                        bool first_pair <- true;
                        
                        loop stop_time_pair over: pairs {
                            if !first_pair { 
                                json_content <- json_content + ","; 
                            }
                            first_pair <- false;
                            
                            bus_stop stop_agent <- stop_time_pair.key;
                            string departure_time <- stop_time_pair.value;
                            
                            // CRITIQUE: Chaque paire est un tableau
                            json_content <- json_content + "[\"" + stop_agent.stopId + "\",\"" + departure_time + "\"]";
                        }
                        
                        // CRITIQUE: Fin tableau
                        json_content <- json_content + "]";
                    }
                    
                    json_content <- json_content + "}}";
                }
                
                json_content <- json_content + "]}";
                
                save json_content to: batch_filename format: "text";
                write "Batch " + batch_number + " : " + length(batch) + " arrêts -> " + batch_filename;
                
            } catch {
                write "❌ Erreur export batch " + batch_number;
            }
            
            current <- end_idx + 1;
            batch_number <- batch_number + 1;
        }
        
        write "✅ Export batch corrigé terminé : " + (batch_number - 1) + " fichiers créés";
    }
    
    action display_final_stats {
        write "\n=== STATISTIQUES FINALES ===";
        write "Total arrêts créés : " + total_stops;
        write "Arrêts de départ : " + departure_stops_count;
        
        if total_stops > 0 {
            float departure_rate <- (departure_stops_count / total_stops) * 100.0;
            write "Taux arrêts de départ : " + int(departure_rate) + "%";
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
        
        write "\n✅ FICHIER JSON CORRIGÉ - VRAIS TABLEAUX GARANTIS";
        write "Compatible avec parser optimisé - Double encodage éliminé";
    }
    
    action debug_departure_structure {
        write "\n=== DEBUG STRUCTURE DEPARTUREINFO ===";
        
        bus_stop sample <- first(bus_stop where (each.departureStopsInfo != nil and !empty(each.departureStopsInfo)));
        if sample = nil {
            write "Aucun arrêt de départ trouvé";
            return;
        }
        
        write "Arrêt échantillon : " + sample.stopId;
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
        
        write "✅ Structure en mémoire OK - Prête pour export corrigé";
    }
    
    // ACTION DE TEST AVEC JSON EN DUR
    action test_with_hardcoded_json {
        write "\n=== TEST AVEC JSON MINIMAL EN DUR ===";
        
        // JSON correct directement dans le code (format que le parser attend)
        string test_json_content <- "{\"departure_stops_info\":[{\"stopId\":\"BRT01_1_S1\",\"location\":[100000,200000],\"routeType\":3,\"departureStopsInfo\":{\"test_trip_1\":[[\"BRT01_1_S1\",\"3600\"],[\"BRT01_1_S2\",\"3900\"],[\"BRT01_1_S3\",\"4200\"]],\"test_trip_2\":[[\"BRT01_1_S1\",\"7200\"],[\"BRT01_1_S4\",\"7500\"]]}}]}";
        
        write "📋 JSON test en dur :\n" + test_json_content;
        
        try {
            map<string, unknown> json_data <- from_json(test_json_content);
            write "✅ Parsing JSON dur réussi";
            
            // Vérification structure
            if json_data contains_key "departure_stops_info" {
                list<map<string, unknown>> stops_list <- list<map<string, unknown>>(json_data["departure_stops_info"]);
                write "✅ Structure attendue : " + length(stops_list) + " stops";
                
                if length(stops_list) > 0 {
                    map<string, unknown> first_stop <- stops_list[0];
                    write "✅ Premier stop keys : " + first_stop.keys;
                    
                    if first_stop contains_key "departureStopsInfo" {
                        map<string, unknown> dep_info <- map<string, unknown>(first_stop["departureStopsInfo"]);
                        write "✅ departureStopsInfo avec " + length(dep_info) + " trips";
                        
                        if !empty(dep_info.keys) {
                            string first_trip <- first(dep_info.keys);
                            unknown trip_data <- dep_info[first_trip];
                            
                            // TEST CRITIQUE: Vérifier que trip_data est une liste
                            try {
                                list<unknown> trip_array <- list<unknown>(trip_data);
                                write "✅ Trip " + first_trip + " est un TABLEAU avec " + length(trip_array) + " éléments";
                                
                                if length(trip_array) > 0 {
                                    unknown first_element <- trip_array[0];
                                    try {
                                        list<string> pair_data <- list<string>(first_element);
                                        if length(pair_data) = 2 {
                                            write "✅ Premier élément est une paire valide : [" + pair_data[0] + ", " + pair_data[1] + "]";
                                            write "🎯 FORMAT JSON CORRECT CONFIRMÉ";
                                        } else {
                                            write "⚠️ Premier élément n'a pas 2 éléments : " + length(pair_data);
                                        }
                                    } catch {
                                        write "❌ Premier élément n'est pas convertible en list<string>";
                                    }
                                }
                            } catch {
                                write "❌ PROBLÈME : Trip " + first_trip + " n'est PAS un tableau !";
                                write "    Type détecté : " + string(trip_data);
                                write "    CAUSE : Double encodage JSON détecté";
                            }
                        }
                    }
                }
            }
            
        } catch {
            write "❌ JSON dur invalide ou non parsable";
        }
        
        write "\n🔍 Ce test valide le format JSON attendu par le parser";
        write "Si ce test réussit, le problème est dans le fichier généré";
    }
    
    // CRÉATION D'UN FICHIER JSON TEST MINIMAL
    action create_minimal_test_json {
        write "\n=== CRÉATION FICHIER JSON TEST MINIMAL ===";
        
        string test_json_path <- export_folder + "test_minimal_correct.json";
        
        // JSON test avec format parfaitement correct
        string test_content <- "{\"departure_stops_info\":[";
        test_content <- test_content + "{\"stopId\":\"TEST_STOP_1\",\"location\":[100000,200000],\"routeType\":3,";
        test_content <- test_content + "\"departureStopsInfo\":{";
        test_content <- test_content + "\"trip_1\":[[\"TEST_STOP_1\",\"3600\"],[\"TEST_STOP_2\",\"3900\"]],";
        test_content <- test_content + "\"trip_2\":[[\"TEST_STOP_1\",\"7200\"],[\"TEST_STOP_3\",\"7500\"]]";
        test_content <- test_content + "}},";
        test_content <- test_content + "{\"stopId\":\"TEST_STOP_2\",\"location\":[200000,300000],\"routeType\":3,";
        test_content <- test_content + "\"departureStopsInfo\":{";
        test_content <- test_content + "\"trip_3\":[[\"TEST_STOP_2\",\"10800\"],[\"TEST_STOP_4\",\"11100\"]]";
        test_content <- test_content + "}}";
        test_content <- test_content + "]}";
        
        try {
            save test_content to: test_json_path format: "text";
            write "✅ Fichier JSON test créé : " + test_json_path;
            write "📏 Taille : " + length(test_content) + " caractères";
            
            // Validation immédiate
            try {
                map<string, unknown> validation <- from_json(test_content);
                write "✅ Validation réussie - JSON test parfaitement formé";
            } catch {
                write "❌ Erreur validation JSON test";
            }
            
        } catch {
            write "❌ Erreur création fichier JSON test";
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

experiment GTFSExperimentFixed type: gui {
    
    parameter "Seuil min trips" var: min_trips_threshold min: 1 max: 10;
    parameter "Max stops/trip" var: max_stops_per_trip min: 10 max: 200;
    parameter "Mode debug" var: debug_mode;
    parameter "Valider JSON" var: validate_json_format;
    
    action export_compact_fixed {
        ask world { do export_departure_stops_compact_fixed; }
    }
    
    action export_light_fixed {
        ask world { do export_departure_stops_light_fixed; }
    }
    
    action export_batch_fixed {
        ask world { do export_departure_stops_batch_fixed; }
    }
    
    action debug_structure {
        ask world { do debug_departure_structure; }
    }
    
    action validate_json {
        ask world { do validate_exported_json; }
    }
    
    action test_json_hardcoded {
        ask world { do test_with_hardcoded_json; }
    }
    
    action create_test_json {
        ask world { do create_minimal_test_json; }
    }
    
    user_command "Export Compact CORRIGÉ" action: export_compact_fixed;
    user_command "Export Ultra-Léger CORRIGÉ" action: export_light_fixed;
    user_command "Export Batch CORRIGÉ" action: export_batch_fixed;
    user_command "Debug Structure" action: debug_structure;
    user_command "Valider JSON Exporté" action: validate_json;
    user_command "Test JSON En Dur" action: test_json_hardcoded;
    user_command "Créer JSON Test Minimal" action: create_test_json;

    output {
        display "Export JSON CORRIGÉ - Vrais Tableaux" background: #white {
            species bus_stop aspect: detailed;
            
            overlay position: {10, 10} size: {450 #px, 160 #px} background: #white transparency: 0.9 border: #black {
                draw "=== EXPORT JSON CORRIGÉ - VRAIS TABLEAUX ===" at: {10#px, 20#px} color: #black font: font("Arial", 11, #bold);
                
                draw "Total arrêts : " + length(bus_stop) at: {20#px, 40#px} color: #black;
                
                int departure_stops <- length(bus_stop where (each.departureStopsInfo != nil and !empty(each.departureStopsInfo)));
                draw "Arrêts départ : " + departure_stops at: {20#px, 60#px} color: #green;
                
                if departure_stops > 0 {
                    int total_trips <- 0;
                    ask bus_stop where (each.departureStopsInfo != nil) {
                        total_trips <- total_trips + length(departureStopsInfo);
                    }
                    draw "Total trips : " + total_trips at: {20#px, 80#px} color: #purple;
                }
                
                draw "✅ DOUBLE ENCODAGE ÉLIMINÉ" at: {20#px, 105#px} color: #green size: 9;
                draw "✅ Format: [...] au lieu de \"[...]\"" at: {20#px, 125#px} color: #green size: 9;
                draw "Compatible avec parser GAMA optimisé" at: {20#px, 145#px} color: #black size: 9;
            }
        }
    }
}