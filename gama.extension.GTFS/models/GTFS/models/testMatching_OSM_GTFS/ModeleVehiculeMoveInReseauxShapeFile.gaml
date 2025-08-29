/**
 * Name: Network_From_Shapefiles_Complete_Optimized_Fixed_Debug
 * Author: Promagicshow95
 * Description: Reconstruction réseau bus + stops avec departureStopsInfo OPTIMISÉ + DIAGNOSTICS RENFORCÉS
 * Tags: shapefile, network, bus, stops, gtfs, reconstruction, optimized, diagnostics, debug
 * Date: 2025-08-28
 * 
 * OPTIMISATION DEPARTUREINFO + DEBUG INTÉGRÉ:
 * - Parse JSON unique au lieu de N fois
 * - Structures globales pour accès O(1)
 * - Conversion automatique stopId -> agents
 * - Compatible simulation véhicules avec horaires
 * - Diagnostics complets pour debugging JSON
 * - Actions de debug renforcées pour résoudre les problèmes de parsing
 */

model Network_From_Shapefiles_Complete_Optimized_Fixed_Debug

global {
    // --- CONFIGURATION FICHIERS ---
    string results_folder <- "../../results/";
    string stops_folder <- "../../results/stopReseau/";
    string export_folder <- "../../results/export/";
    
    file data_file <- shape_file("../../includes/shapeFileHanoishp.shp");
    geometry shape <- envelope(data_file);
    
    // --- VARIABLES STATISTIQUES ---
    int total_bus_routes <- 0;
    int total_bus_stops <- 0;
    int total_network_elements <- 0;
    
    // --- PARAMÈTRES D'AFFICHAGE ---
    bool show_routes <- true;
    bool show_stops <- true;
    
    // --- PARAMÈTRES DEBUG ---
    bool debug_mode <- true;
    bool force_parsing <- false;
    string working_json_file <- "";
    
    // STRUCTURES OPTIMISÉES DEPARTUREINFO
    // Étape 1: Structure temporaire pour parsing JSON
    map<string, map<string, list<pair<string, int>>>> stop_to_all_trips;
    // stopId -> tripId -> [(stopId, heure), (stopId, heure)...]
    
    // Étape 2: Map de conversion
    map<string, bus_stop> stopId_to_agent;
    // "01_1_S1" -> agent_bus_stop_123
    
    // Étape 3: Structure finale optimisée
    map<string, list<pair<bus_stop, int>>> trip_to_agents_with_times;
    // "01_1_MD_1" -> [(agent_S1, 34200), (agent_S2, 34467)...]
    
    // Étape 4: Structure trip -> route OSM
    map<string, string> trip_to_osm_route;
    // "01_1_MD_1" -> "way_123456789"
    
    // Statistiques optimisation
    int json_parse_time <- 0;
    int total_trips_found <- 0;
    int successful_conversions <- 0;

    init {
        write "=== RÉSEAU BUS AVEC DEPARTUREINFO OPTIMISÉ + DIAGNOSTICS RENFORCÉS ===";
        
        // ÉTAPE 1: CHARGEMENT STANDARD
        if show_routes {
            do load_bus_network_robust;
        }
        if show_stops {
            do load_gtfs_stops_from_shapefile;
        }
        
        // ÉTAPE 2: DIAGNOSTIC JSON RENFORCÉ
        do debug_json_parsing_detailed;
        
        // ÉTAPE 3: TENTATIVE DE PARSING AUTOMATIQUE
        if working_json_file != "" {
            do build_optimized_departure_structures;
        } else {
            write "ATTENTION: Aucun fichier JSON valide trouvé - structures restent vides";
            write "SOLUTION: Utilisez les commandes debug ou créez le fichier JSON manquant";
        }
        
        // ÉTAPE 4: VALIDATION ET STATS
        do validate_world_envelope;
        do display_optimized_statistics;
        do validate_loaded_data;
    }
    
    // CHARGEMENT RÉSEAU BUS
    action load_bus_network_robust {
        write "\nCHARGEMENT RÉSEAU BUS";
        
        int bus_parts_loaded <- 0;
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
                
                int routes_in_file <- length(shape_file_bus);
                bus_routes_count <- bus_routes_count + routes_in_file;
                bus_parts_loaded <- bus_parts_loaded + 1;
                
                write "  Part " + i + " : " + routes_in_file + " routes";
                i <- i + 1;
                
            } catch {
                write "  Fin détection à part" + i;
                continue_loading <- false;
            }
        }
        
        total_bus_routes <- bus_routes_count;
        write "TOTAL BUS : " + bus_routes_count + " routes";
    }
    
    // CHARGEMENT ARRÊTS
    action load_gtfs_stops_from_shapefile {
        write "\nCHARGEMENT STOPS";
        
        string stops_filename <- stops_folder + "gtfs_stops_complete.shp";
        
        try {
            file shape_file_stops <- shape_file(stops_filename);
            
            create bus_stop from: shape_file_stops with: [
                stopId::string(read("stopId")),
                stop_name::string(read("name")),
                stopName::string(read("stopName")),
                routeType::int(read("routeType")),
                tripNumber::int(read("tripNumber")),
                closest_route_id::string(read("closest_id")),
                closest_route_index::int(read("closest_idx")),
                closest_route_dist::float(read("distance")),
                is_matched_str::string(read("matched")),
                match_quality::string(read("quality")),
                zone_id::int(read("zone_id"))
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
            
            write "" + total_bus_stops + " arrêts chargés";
            
        } catch {
            write "ERREUR chargement stops";
            total_bus_stops <- 0;
        }
    }
    
    // ========== ACTIONS DE DEBUG RENFORCÉES ==========
    
    // DEBUG DÉTAILLÉ PARSING JSON
    action debug_json_parsing_detailed {
        write "\nDEBUG JSON PARSING";
        
        string json_filename <- stops_folder + "departure_stops_info_stopid.json";
        
        // Test existence fichier principal
        try {
            file test_f <- text_file(json_filename);
            string content <- string(test_f);
            
            if length(content) > 0 {
                write "✅ Fichier JSON trouvé : " + json_filename;
                write "   Taille : " + length(content) + " caractères";
                working_json_file <- json_filename;
                
                // Test parsing rapide
                try {
                    map<string, unknown> parsed <- from_json(content);
                    
                    if parsed contains_key "departure_stops_info" {
                        list<unknown> stops_list <- list<unknown>(parsed["departure_stops_info"]);
                        write "✅ Structure valide : " + length(stops_list) + " arrêts";
                    } else {
                        write "⚠️ Clé 'departure_stops_info' manquante";
                    }
                    
                } catch {
                    write "❌ JSON format invalide";
                }
            } else {
                write "❌ Fichier JSON vide";
            }
            
        } catch {
            write "❌ Fichier JSON non trouvé : " + json_filename;
            
            // Recherche fichiers alternatifs
            list<string> alternatives <- [
                stops_folder + "departure_stops_info.json",
                stops_folder + "stops_info.json"
            ];
            
            loop alt_file over: alternatives {
                try {
                    file alt_f <- text_file(alt_file);
                    string alt_content <- string(alt_f);
                    if length(alt_content) > 0 {
                        write "✅ Fichier alternatif trouvé : " + alt_file;
                        working_json_file <- alt_file;
                        break;
                    }
                } catch {
                    // Continue searching
                }
            }
            
            if working_json_file = "" {
                write "❌ Aucun fichier JSON valide trouvé";
                write "💡 Solution : Générez d'abord le fichier JSON avec le modèle d'export";
            }
        }
    }
    
    // DEBUG EXTRACTION TRIPS DÉTAILLÉ - ACTION CRITIQUE
    action debug_trip_extraction_detailed {
        write "\n=== DEBUG EXTRACTION TRIPS DÉTAILLÉ ===";
        
        if working_json_file = "" {
            write "❌ Aucun fichier JSON configuré";
            return;
        }
        
        try {
            // Relire le fichier
            file json_f <- text_file(working_json_file);
            string content <- string(json_f);
            map<string, unknown> json_data <- from_json(content);
            
            write "✅ Fichier relu et parsé";
            
            // Accéder aux arrêts
            list<map<string, unknown>> stops_list <- list<map<string, unknown>>(json_data["departure_stops_info"]);
            write "📊 Nombre total d'arrêts : " + length(stops_list);
            
            // Analyser les 5 premiers arrêts en détail
            int max_debug <- min(5, length(stops_list));
            int stops_with_trips <- 0;
            int total_trips_found_debug <- 0;
            write "max debug is: "+max_debug;
            
            loop i from: 0 to: (max_debug - 1) {
                map<string, unknown> stop_data <- stops_list[i];
                string stop_id <- string(stop_data["stopId"]);
                
                write "\n🚏 ARRÊT " + (i + 1) + " : " + stop_id;
                write "   Clés disponibles : " + stop_data.keys;
                
                // Test routeType
                if stop_data contains_key "routeType" {
                    int route_type <- int(stop_data["routeType"]);
                    write "   RouteType : " + route_type + (route_type = 3 ? " ✅ (bus)" : " ❌ (pas bus)");
                    
                    if route_type != 3 {
                        write "   ⚠️ ARRÊT IGNORÉ : routeType != 3";
                        continue;
                    }
                } else {
                    write "   RouteType : non défini (accepté comme bus)";
                }
                
                // Test departureStopsInfo
                write "debug stop data from departureStopsInfo:" + stop_data["departureStopsInfo"];
                if stop_data contains_key "departureStopsInfo" {
                    map<string, unknown> departure_info <- map<string, unknown>(stop_data["departureStopsInfo"]);
                    write "   ✅ departureStopsInfo présent";
                    write "   Trips disponibles : " + departure_info.keys;
                    write "   Nombre de trips : " + length(departure_info);
                    
                    if length(departure_info) = 0 {
                        write "   ❌ PROBLÈME : departureStopsInfo vide";
                        continue;
                    }
                    
                    stops_with_trips <- stops_with_trips + 1;
                    
                    // Analyser chaque trip dans ce stop
                    int trip_count <- 0;
                    loop trip_id over: departure_info.keys {
                        trip_count <- trip_count + 1;
                        unknown trip_data <- departure_info[trip_id];
                        
                        write "   \n   🚌 TRIP " + trip_count + " : " + trip_id;
                        write "      Type de données brut : " + string(trip_data);
                        
                        try {
                            list<unknown> trip_array <- list<unknown>(trip_data);
                            write "      ✅ Conversion en list<unknown> réussie";
                            write "      Nombre d'éléments : " + length(trip_array);
                            
                            if length(trip_array) = 0 {
                                write "      ❌ PROBLÈME : Tableau trip vide";
                                continue;
                            }
                            
                            // Analyser les 3 premiers éléments
                            int max_elements <- min(3, length(trip_array));
                            int valid_pairs <- 0;
                            
                            loop j from: 0 to: (max_elements - 1) {
                                unknown element <- trip_array[j];
                                write "      \n      📍 ÉLÉMENT " + (j + 1) + " : " + string(element);
                                
                                try {
                                    list<string> pair_data <- list<string>(element);
                                    write "         ✅ Conversion en list<string> réussie";
                                    write "         Longueur : " + length(pair_data);
                                    
                                    if length(pair_data) >= 2 {
                                        string stop_id_in_trip <- pair_data[0];
                                        string time_str <- pair_data[1];
                                        
                                        write "         StopId : " + stop_id_in_trip;
                                        write "         Time : " + time_str;
                                        
                                        try {
                                            int time_seconds <- int(time_str);
                                            write "         ✅ Time en secondes : " + time_seconds;
                                            valid_pairs <- valid_pairs + 1;
                                        } catch {
                                            write "         ❌ ERREUR conversion time : " + time_str;
                                        }
                                    } else {
                                        write "         ❌ ERREUR : pair_data trop court (" + length(pair_data) + ")";
                                    }
                                    
                                } catch {
                                    write "         ❌ ERREUR conversion vers list<string>";
                                }
                            }
                            
                            write "      📊 Paires valides dans ce trip : " + valid_pairs + "/" + length(trip_array);
                            
                            if valid_pairs > 0 {
                                total_trips_found_debug <- total_trips_found_debug + 1;
                                write "      ✅ TRIP VALIDE";
                            } else {
                                write "      ❌ TRIP INVALIDE : aucune paire valide";
                            }
                            
                        } catch {
                            write "      ❌ ERREUR conversion vers list<unknown>";
                            write "      Type réel : " + string(trip_data);
                        }
                    }
                    
                } else {
                    write "   ❌ PROBLÈME : departureStopsInfo manquant";
                }
            }
            
            write "\n📊 RÉSUMÉ DEBUG :";
            write "   Arrêts analysés : " + max_debug;
            write "   Arrêts avec trips : " + stops_with_trips;
            write "   Trips valides trouvés : " + total_trips_found_debug;
            
            if total_trips_found_debug = 0 {
                write "\n💡 DIAGNOSTIC :";
                if stops_with_trips = 0 {
                    write "   CAUSE : Aucun arrêt n'a de departureStopsInfo";
                    write "   SOLUTION : Vérifiez la structure JSON";
                } else {
                    write "   CAUSE : Trips présents mais invalides";
                    write "   SOLUTION : Vérifiez le format des données trip";
                }
            } else {
                write "\n✅ Des trips valides existent - problème dans l'action de parsing principale";
            }
            
        } catch {
            write "❌ ERREUR dans debug_trip_extraction_detailed";
        }
    }
    
    // FORCE PARSING AVEC FICHIER CORRECT
    action force_parse_with_correct_file {
        write "\nFORCE PARSING AVEC FICHIER CORRECT";
        
        if working_json_file = "" {
            list<string> candidates <- [
                stops_folder + "departure_stops_info_stopid.json",
                stops_folder + "departure_stops_info.json", 
                stops_folder + "stops_info.json"
            ];
            
            loop candidate over: candidates {
                try {
                    file test_f <- text_file(candidate);
                    string content <- string(test_f);
                    if length(content) > 100 {
                        working_json_file <- candidate;
                        write "Fichier sélectionné : " + candidate;
                        break;
                    }
                } catch {
                    // Continue searching
                }
            }
        }
        
        if working_json_file = "" {
            write "Aucun fichier JSON valide trouvé !";
            return;
        }
        
        try {
            file my_json_f <- text_file(working_json_file);
            string content <- string(my_json_f);
            map<string, unknown> json_data <- from_json(content);
            
            write "Parsing forcé réussi avec : " + working_json_file;
            
            // Reset et reconstruction
            stop_to_all_trips <- map<string, map<string, list<pair<string, int>>>>([]);
            
            // Parser avec la structure correcte
            do parse_json_data_correct_structure(json_data);
            
            // Construire les autres structures
            do build_stopId_to_agent_map;
            do convert_to_final_structure;
            
            // Résultats
            write "RÉSULTATS FORCE PARSING :";
            write "   stop_to_all_trips : " + length(stop_to_all_trips);
            write "   trip_to_agents_with_times : " + length(trip_to_agents_with_times);
            write "   trip_to_osm_route : " + length(trip_to_osm_route);
            
        } catch {
            write "Force parsing échoué avec : " + working_json_file;
        }
    }
    
    // TEST STRUCTURE MINIMALE
    action test_minimal_json_structure {
        write "\nTEST STRUCTURE JSON MINIMALE";
        
        // Créer une structure test minimale
        map<string, map<string, list<pair<string, int>>>> test_structure <- map([]);
        
        // Ajouter quelques stops test
        int test_stops <- min(3, length(bus_stop));
        
        if test_stops > 0 {
            list<bus_stop> sample_stops <- copy(bus_stop, 0, test_stops);
            
            loop i from: 0 to: test_stops - 1 {
                bus_stop stop <- sample_stops[i];
                string test_stop_id <- stop.stopId;
                
                map<string, list<pair<string, int>>> test_trips <- map([]);
                list<pair<string, int>> test_schedule <- [
                    pair(test_stop_id, 3600 + i * 300),
                    pair(test_stop_id, 3900 + i * 300)
                ];
                test_trips["test_trip_" + i] <- test_schedule;
                test_structure[test_stop_id] <- test_trips;
            }
        } else {
            // Créer structure test sans agents existants
            map<string, list<pair<string, int>>> test_trips <- map([]);
            list<pair<string, int>> test_schedule <- [pair("test_stop_1", 3600), pair("test_stop_2", 3660)];
            test_trips["test_trip_1"] <- test_schedule;
            test_structure["test_stop_1"] <- test_trips;
        }
        
        write "Structure test créée avec " + length(test_structure) + " stops";
        
        // Simuler le processus de conversion
        stop_to_all_trips <- test_structure;
        
        // Test conversion vers agents
        if length(bus_stop) > 0 {
            do build_stopId_to_agent_map;
            do convert_to_final_structure;
            
            write "RÉSULTATS TEST :";
            write "   trip_to_agents_with_times : " + length(trip_to_agents_with_times);
            write "   successful_conversions : " + successful_conversions;
        } else {
            write "Aucun bus_stop disponible pour le test de conversion";
        }
    }
    
    // ========== ACTIONS PRINCIPALES DE PARSING ==========
    
    // CONSTRUCTION STRUCTURES OPTIMISÉES
    action build_optimized_departure_structures {
        write "\nCONSTRUCTION STRUCTURES OPTIMISÉES";
        
        if working_json_file = "" {
            write "ERREUR : Aucun fichier JSON disponible";
            return;
        }
        
        // ÉTAPE 1: Parse unique JSON
        do parse_json_to_temporary_structure;
        
        // Vérification critique
        if length(stop_to_all_trips) = 0 {
            write "ERREUR CRITIQUE : Parsing JSON échoué - structures vides";
            write "SOLUTIONS :";
            write "  1. Utilisez 'Debug Trips Détaillé' pour identifier le problème";
            write "  2. Utilisez 'Force Parsing' pour forcer le processus";
            return;
        }
        
        // ÉTAPE 2: Construire map conversion
        do build_stopId_to_agent_map;
        
        // ÉTAPE 3: Convertir vers structure finale
        do convert_to_final_structure;
        
        write "Structures optimisées construites avec succès";
    }
    
    // PARSE UNIQUE JSON
    action parse_json_to_temporary_structure {
        write "Parse JSON unique...";
        
        if working_json_file = "" {
            write "ERREUR : working_json_file vide";
            return;
        }
        
        // Initialiser structure temporaire
        stop_to_all_trips <- map<string, map<string, list<pair<string, int>>>>([]);
        
        try {
            // Lecture fichier
            file json_text_f <- text_file(working_json_file);
            string file_content <- string(json_text_f);
            
            if length(file_content) = 0 {
                write "ERREUR : Fichier JSON vide";
                return;
            }
            
            // Parsing JSON
            map<string, unknown> json_data <- from_json(file_content);
            write "✅ JSON parsing réussi - " + length(file_content) + " caractères";
            
            // Traitement des données
            do parse_json_data_correct_structure(json_data);
            
        } catch {
            write "❌ Erreur parsing JSON : " + working_json_file;
        }
    }
    
    // PARSER JSON AVEC STRUCTURE CORRECTE
    action parse_json_data_correct_structure(map<string, unknown> json_data) {
        write "Analyse structure JSON...";
        
        try {
            // Accéder à departure_stops_info
            list<map<string, unknown>> stops_list;
            
            if json_data contains_key "departure_stops_info" {
                stops_list <- list<map<string, unknown>>(json_data["departure_stops_info"]);
                write "Nombre d'arrêts dans JSON : " + length(stops_list);
            } else {
                write "ERREUR : Clé 'departure_stops_info' manquante";
                return;
            }
            
            if length(stops_list) = 0 {
                write "ERREUR : Aucun arrêt trouvé dans la structure JSON";
                return;
            }
            
            // PROCESSING PRINCIPAL
            int processed_stops <- 0;
            int processed_trips <- 0;
            
            // Traiter chaque stop
            loop stop_data over: stops_list {
                string stop_id <- string(stop_data["stopId"]);
                
                // Validation routeType = 3 (bus) si présent
                bool is_bus_stop <- true;
                if stop_data contains_key "routeType" {
                    int route_type <- int(stop_data["routeType"]);
                    is_bus_stop <- (route_type = 3);
                }
                
                if stop_id != nil and stop_id != "" and is_bus_stop {
                    processed_stops <- processed_stops + 1;
                    
                    // Initialiser pour ce stop
                    if !(stop_to_all_trips contains_key stop_id) {
                        stop_to_all_trips[stop_id] <- map<string, list<pair<string, int>>>([]);
                    }
                    
                    // Accéder au departureStopsInfo
                    if stop_data contains_key "departureStopsInfo" {
                        map<string, unknown> departure_info <- map<string, unknown>(stop_data["departureStopsInfo"]);
                        
                        // Traiter chaque trip
                        loop trip_id over: departure_info.keys {
                            unknown trip_data_raw <- departure_info[trip_id];
                            
                            try {
                                // CRITIQUE: trip_data_raw est directement un tableau JSON
                                list<unknown> trip_array <- list<unknown>(trip_data_raw);
                                list<pair<string, int>> trip_schedule <- [];
                                
                                // Convertir chaque paire [stopId, time]
                                loop stop_time_element over: trip_array {
                                    try {
                                        list<string> pair_data <- list<string>(stop_time_element);
                                        
                                        if length(pair_data) >= 2 {
                                            string stop_id_in_trip <- pair_data[0];
                                            int time_seconds <- int(pair_data[1]);
                                            
                                            if time_seconds > 0 {
                                                trip_schedule <+ pair(stop_id_in_trip, time_seconds);
                                            }
                                        }
                                    } catch {
                                        // Ignore les éléments mal formés
                                    }
                                }
                                
                                // Stocker si non vide
                                if !empty(trip_schedule) {
                                    stop_to_all_trips[stop_id][trip_id] <- trip_schedule;
                                    processed_trips <- processed_trips + 1;
                                }
                                
                            } catch {
                                // Erreur silencieuse pour éviter spam
                            }
                        }
                    }
                }
            }
            
            total_trips_found <- processed_trips;
            write "✅ Parsing terminé : " + processed_stops + " arrêts, " + processed_trips + " trips";
            
        } catch {
            write "❌ ERREUR critique dans parse_json_data_correct_structure";
        }
    }
    
    // CONSTRUIRE MAP CONVERSION
    action build_stopId_to_agent_map {
        write "Construction map stopId -> agent...";
        
        stopId_to_agent <- map<string, bus_stop>([]);
        
        ask bus_stop {
            if stopId != nil and stopId != "" {
                stopId_to_agent[stopId] <- self;
            }
        }
        
        write "" + length(stopId_to_agent) + " conversions créées";
    }
    
    // CONVERTIR VERS STRUCTURE FINALE
    action convert_to_final_structure {
        write "Conversion vers structure finale...";
        
        trip_to_agents_with_times <- map<string, list<pair<bus_stop, int>>>([]);
        successful_conversions <- 0;
        
        // Pour chaque stop dans structure temporaire
        loop stop_id over: stop_to_all_trips.keys {
            map<string, list<pair<string, int>>> trips_from_stop <- stop_to_all_trips[stop_id];
            
            // Pour chaque trip depuis ce stop
            loop trip_id over: trips_from_stop.keys {
                if !(trip_to_agents_with_times contains_key trip_id) {
                    list<pair<string, int>> schedule <- trips_from_stop[trip_id];
                    list<pair<bus_stop, int>> agents_with_times <- [];
                    
                    // Convertir stopId -> agents
                    bool conversion_success <- true;
                    loop stop_time_pair over: schedule {
                        string stop_id_in_trip <- stop_time_pair.key;
                        int time <- stop_time_pair.value;
                        
                        if stopId_to_agent contains_key stop_id_in_trip {
                            bus_stop stop_agent <- stopId_to_agent[stop_id_in_trip];
                            agents_with_times <+ pair(stop_agent, time);
                        } else {
                            conversion_success <- false;
                            break;
                        }
                    }
                    
                    // Stocker si succès
                    if conversion_success and !empty(agents_with_times) {
                        trip_to_agents_with_times[trip_id] <- agents_with_times;
                        successful_conversions <- successful_conversions + 1;
                    }
                }
            }
        }
        
        write "" + successful_conversions + " trips convertis avec agents + horaires";
        
        // Construction liaison trip -> route OSM
        do build_trip_to_osm_mapping;
    }
    
    // CONSTRUCTION LIAISON TRIP -> ROUTE OSM
    action build_trip_to_osm_mapping {
        write "Construction liaison trip -> route OSM...";
        
        trip_to_osm_route <- map<string, string>([]);
        int successful_mappings <- 0;
        
        // Pour chaque trip dans trip_to_agents_with_times
        loop trip_id over: trip_to_agents_with_times.keys {
            list agents_route <- trip_to_agents_with_times[trip_id];
            
            // Compter les votes pour chaque OSM route
            map<string, int> osm_votes <- map<string, int>([]);
            
            loop agent_pair over: agents_route {
                pair<bus_stop, int> stop_time_pair <- agent_pair;
                bus_stop stop_agent <- stop_time_pair.key;
                
                if stop_agent.closest_route_id != nil and stop_agent.closest_route_id != "" {
                    string osm_id <- stop_agent.closest_route_id;
                    
                    if osm_votes contains_key osm_id {
                        osm_votes[osm_id] <- osm_votes[osm_id] + 1;
                    } else {
                        osm_votes[osm_id] <- 1;
                    }
                }
            }
            
            // Trouver la route majoritaire
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
        
        write "" + successful_mappings + " trips liés à des routes OSM";
    }
    
    // ========== APIs D'ACCÈS OPTIMISÉES ==========
    
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
    
    list get_trips_from_stop(string stop_id) {
        if stop_to_all_trips contains_key stop_id {
            return stop_to_all_trips[stop_id].keys;
        }
        return [];
    }
    
    string get_osm_route_for_trip(string trip_id) {
        if trip_to_osm_route contains_key trip_id {
            return trip_to_osm_route[trip_id];
        }
        return "";
    }
    
    bus_route get_route_agent_for_trip(string trip_id) {
        string osm_id <- get_osm_route_for_trip(trip_id);
        if osm_id != "" {
            return first(bus_route where (each.osm_id = osm_id));
        }
        return nil;
    }
    
    // STATISTIQUES OPTIMISÉES
    action display_optimized_statistics {
        write "\nSTATISTIQUES OPTIMISÉES";
        write "Routes Bus : " + total_bus_routes;
        write "Arrêts GTFS : " + total_bus_stops;
        write "Trips trouvés : " + total_trips_found;
        write "Conversions réussies : " + successful_conversions;
        write "Fichier JSON utilisé : " + (working_json_file != "" ? working_json_file : "AUCUN");
        write "Structures en mémoire :";
        write "  - stop_to_all_trips : " + length(stop_to_all_trips);
        write "  - stopId_to_agent : " + length(stopId_to_agent);
        write "  - trip_to_agents_with_times : " + length(trip_to_agents_with_times);
        write "  - trip_to_osm_route : " + length(trip_to_osm_route);
        
        // Diagnostic si structures vides
        if length(trip_to_agents_with_times) = 0 {
            write "\nDIAGNOSTIC STRUCTURES VIDES :";
            if working_json_file = "" {
                write "  CAUSE : Aucun fichier JSON trouvé";
                write "  SOLUTION : Génération JSON requise";
            } else if length(stop_to_all_trips) = 0 {
                write "  CAUSE : Parsing JSON échoué";
                write "  SOLUTION : Utilisez 'Debug Trips Détaillé'";
            } else if length(stopId_to_agent) = 0 {
                write "  CAUSE : Aucun bus_stop chargé";
                write "  SOLUTION : Vérifiez le shapefile des arrêts";
            } else {
                write "  CAUSE : Conversion stopId->agents échouée";
                write "  SOLUTION : Vérifiez correspondance JSON/shapefile";
            }
        }
        
        // Exemple d'utilisation si données disponibles
        if !empty(trip_to_agents_with_times) {
            string sample_trip <- first(trip_to_agents_with_times.keys);
            list sample_route <- trip_to_agents_with_times[sample_trip];
            string osm_route <- get_osm_route_for_trip(sample_trip);
            
            write "\nExemple d'utilisation :";
            write "  Trip : " + sample_trip;
            write "  Arrêts dans ce trip : " + length(sample_route);
            write "  Route OSM liée : " + osm_route;
        }
    }
    
    // ACTIONS UTILITAIRES
    action validate_world_envelope {
        write "\nVALIDATION ENVELOPPE";
        if shape != nil {
            write "Enveloppe définie : " + shape.width + " x " + shape.height;
        } else {
            write "Enveloppe non définie";
        }
    }
    
    action validate_loaded_data {
        write "\nVALIDATION DONNÉES";
        
        if length(bus_route) > 0 {
            bus_route sample_route <- first(bus_route);
            write "Échantillon Route : " + (sample_route.route_name != nil ? sample_route.route_name : "VIDE");
        }
        
        if length(bus_stop) > 0 {
            bus_stop sample_stop <- first(bus_stop);
            write "Échantillon Arrêt : " + (sample_stop.stopId != nil ? sample_stop.stopId : "VIDE");
        }
        
        write "VALIDATION TERMINÉE";
    }
    
    // ACTION RECHARGEMENT COMPLET
    action reload_optimized_network {
        write "\nRECHARGEMENT OPTIMISÉ COMPLET";
        
        ask bus_route { do die; }
        ask bus_stop { do die; }
        
        total_bus_routes <- 0;
        total_bus_stops <- 0;
        working_json_file <- "";
        
        // Reset structures
        stop_to_all_trips <- map<string, map<string, list<pair<string, int>>>>([]);
        stopId_to_agent <- map<string, bus_stop>([]);
        trip_to_agents_with_times <- map<string, list<pair<bus_stop, int>>>([]);
        trip_to_osm_route <- map<string, string>([]);
        
        if show_routes { do load_bus_network_robust; }
        if show_stops { do load_gtfs_stops_from_shapefile; }
        
        do debug_json_parsing_detailed;
        
        if working_json_file != "" {
            do build_optimized_departure_structures;
        }
        
        do display_optimized_statistics;
        
        write "Rechargement optimisé terminé";
    }
}

// ESPÈCES D'AGENTS
species bus_route {
    string route_name;
    string osm_id;
    string route_type;
    string highway_type;
    float length_meters;
    int zone_id;
    
    aspect default {
        if shape != nil {
            draw shape color: #blue width: 1.5;
        }
    }
}

species bus_stop {
    string stopId <- "";
    string stop_name <- "";
    string stopName <- "";
    int routeType <- 0;
    int tripNumber <- 0;
    
    // Attributs de matching
    string closest_route_id <- "";
    int closest_route_index <- -1;
    float closest_route_dist <- -1.0;
    bool is_matched <- false;
    string is_matched_str <- "FALSE";
    string match_quality <- "NONE";
    int zone_id;
    
    aspect default {
        draw circle(100.0) color: #red;
        
        // Indicateur si ce stop a des trips
        list trips <- world.get_trips_from_stop(stopId);
        if !empty(trips) {
            draw circle(150.0) border: #blue width: 2;
            draw string(length(trips)) at: location + {0, 200} color: #blue size: 12;
        }
    }
}

// EXPÉRIMENT AVEC DEBUG COMPLET
experiment network_optimized_debug type: gui {
    
    // Actions de base
    action reload_all {
        ask world { do reload_optimized_network; }
    }
    
    action show_stats {
        ask world { do display_optimized_statistics; }
    }
    
    // Actions de debug
    action debug_json {
        ask world { do debug_json_parsing_detailed; }
    }
    
    action force_parsing {
        ask world { do force_parse_with_correct_file; }
    }
    
    action test_minimal {
        ask world { do test_minimal_json_structure; }
    }
    
    action debug_trips_detailed {
        ask world { do debug_trip_extraction_detailed; }
    }
    
    // Commandes utilisateur
    user_command "Recharger Complet" action: reload_all;
    user_command "Afficher Stats" action: show_stats;
    user_command "Debug JSON Détaillé" action: debug_json;
    user_command "Force Parsing" action: force_parsing;
    user_command "Test Structure Minimale" action: test_minimal;
    user_command "Debug Trips Détaillé" action: debug_trips_detailed;
    
    output {
        display "Réseau Bus Optimisé + Debug" background: #white type: 2d {
            species bus_route aspect: default;
            species bus_stop aspect: default;
            
            overlay position: {10, 10} size: {450 #px, 200 #px} background: #white transparency: 0.9 border: #black {
                draw "=== RÉSEAU BUS OPTIMISÉ + DEBUG AVANCÉ ===" at: {10#px, 20#px} color: #black font: font("Arial", 12, #bold);
                
                draw "Routes : " + length(bus_route) at: {20#px, 45#px} color: #blue;
                draw "Arrêts : " + length(bus_stop) at: {20#px, 65#px} color: #red;
                
                // Stats optimisation avec diagnostic
                if world.successful_conversions > 0 {
                    draw "Trips convertis : " + world.successful_conversions at: {20#px, 85#px} color: #green;
                    draw "Trips->Routes OSM : " + length(world.trip_to_osm_route) at: {20#px, 105#px} color: #purple;
                    draw "STATUS: JSON parsing réussi" at: {20#px, 125#px} color: #green;
                } else {
                    draw "STATUS: Parsing en attente" at: {20#px, 85#px} color: #red;
                    if world.working_json_file = "" {
                        draw "CAUSE: Fichier JSON manquant" at: {20#px, 105#px} color: #orange;
                    } else {
                        draw "CAUSE: Trips non extraits" at: {20#px, 105#px} color: #orange;
                        draw "SOLUTION: 'Debug Trips Détaillé'" at: {20#px, 125#px} color: #orange;
                    }
                }
                
                draw "Conversions stopId->agent : " + length(world.stopId_to_agent) at: {20#px, 145#px} color: #gray;
                draw "Fichier JSON: " + (world.working_json_file != "" ? "TROUVÉ" : "MANQUANT") at: {20#px, 165#px} color: (world.working_json_file != "" ? #green : #red);
            }
        }
    }
}