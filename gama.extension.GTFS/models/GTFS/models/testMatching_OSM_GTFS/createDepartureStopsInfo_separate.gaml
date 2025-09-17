/**
 * Name: ModeleReseauBusAvecJsonParser
 * Author: Adapted - Combined Network + JSON Processing
 * Description: Chargement réseau bus/arrêts + parsing données JSON horaires
 */

model ModeleReseauBusAvecJsonParser

global {
    // ====================================
    // CONFIGURATION FICHIERS
    // ====================================
    string results_folder <- "../../results/";
    string stops_folder <- "../../results/stopReseau/";
    
    file data_file <- shape_file("../../includes/shapeFileHanoishp.shp");
    geometry shape <- envelope(data_file);
    
    // ====================================
    // VARIABLES RÉSEAU BUS (ModeleReseauBusSimple)
    // ====================================
    int total_bus_routes <- 0;
    int total_bus_stops <- 0;
    int matched_stops <- 0;
    int unmatched_stops <- 0;
    bool debug_mode <- true;
    
    // STRUCTURES RÉSEAU
    map<string, bus_stop> stopId_to_agent;
    map<string, bus_route> osmId_to_route;
    
    // ====================================
    // VARIABLES PARSER JSON (MODIFIÉES)
    // ====================================
    map<string, list<string>> trip_to_stop_ids;
    map<string, list<int>> trip_to_departure_times;
    map<string, list<pair<bus_stop,int>>> trip_to_pairs;  // ← MODIFIÉ: bus_stop au lieu de string
    
    // NOUVELLES VARIABLES POUR LIAISON TRIP → ROUTE
    map<string, bus_route> tripId_to_main_route;
    map<string, list<bus_route>> tripId_to_all_routes;  // optionnel pour cas complexes
    map<string, map<string, int>> tripId_to_route_frequencies;  // debug/analyse
    
    // CACHE DE PERFORMANCE  
    bool use_performance_cache <- true;
    
    // ====================================
    // INITIALISATION COMBINÉE
    // ====================================
    init {
        write "=== MODÈLE COMBINÉ : RÉSEAU BUS + PARSER JSON ===";
        
        // PHASE 1 : CHARGEMENT RÉSEAU
        write "\n▶ PHASE 1 : CHARGEMENT RÉSEAU BUS";
        do load_bus_network;
        do load_gtfs_stops;
        do build_basic_mappings;
        do display_network_statistics;
        
        // PHASE 2 : PARSING JSON
        write "\n▶ PHASE 2 : PARSING DONNÉES JSON";
        do load_json_robust;
        
        write "\n=== INITIALISATION TERMINÉE ===";
    }
    
    // ####################################
    // SECTION RÉSEAU BUS (INCHANGÉE)
    // ####################################
    
    // CHARGEMENT RÉSEAU BUS
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
                
                if debug_mode {
                    write "Fichier " + i + " : " + length(shape_file_bus) + " routes";
                }
                
            } catch {
                if debug_mode {
                    write "Fin chargement à l'index : " + i;
                }
                continue_loading <- false;
            }
        }
        
        total_bus_routes <- bus_routes_count;
        write "Routes chargées : " + bus_routes_count;
        
        // Nettoyer les routes sans géométrie
        ask bus_route where (each.shape = nil) {
            do die;
        }
        
        total_bus_routes <- length(bus_route);
        write "Routes avec géométrie valide : " + total_bus_routes;
    }
    
    // CHARGEMENT ARRÊTS GTFS
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
            
            // Nettoyer et valider les arrêts
            ask bus_stop {
                is_matched <- (is_matched_str = "TRUE");
                
                if stopId = nil or stopId = "" {
                    stopId <- "stop_" + string(int(self));
                }
                if stop_name = nil or stop_name = "" {
                    stop_name <- "Stop_" + string(int(self));
                }
                
                // Compter les arrêts matchés/non-matchés
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
            write "ERREUR : Impossible de charger " + stops_filename;
            write "Vérifiez que le fichier existe et est accessible";
            total_bus_stops <- 0;
        }
    }
    
    // CONSTRUCTION MAPPINGS BASIQUES
    action build_basic_mappings {
        write "\n3. CONSTRUCTION MAPPINGS";
        
        // Mapping stopId -> agent
        stopId_to_agent <- map<string, bus_stop>([]);
        ask bus_stop {
            if stopId != nil and stopId != "" {
                stopId_to_agent[stopId] <- self;
            }
        }
        
        // Mapping osmId -> route
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
    
    // STATISTIQUES RÉSEAU
    action display_network_statistics {
        // Calculs silencieux des statistiques
        if total_bus_routes > 0 {
            map<string, int> route_type_counts <- map<string, int>([]);
            ask bus_route {
                if route_type != nil {
                    route_type_counts[route_type] <- (route_type_counts contains_key route_type) ? route_type_counts[route_type] + 1 : 1;
                }
            }
        }
        
        if matched_stops > 0 {
            float total_distance <- 0.0;
            int distance_count <- 0;
            ask bus_stop where (each.is_matched and each.closest_route_dist > 0) {
                total_distance <- total_distance + closest_route_dist;
                distance_count <- distance_count + 1;
            }
        }
    }
    
    // ####################################
    // SECTION PARSER JSON (INCHANGÉE)
    // ####################################
    
    action load_json_robust {
        write "\n4. LECTURE ET PARSING JSON";
        
        string json_filename <- stops_folder + "departure_stops_separated.json";
        
        try {
            file json_f <- text_file(json_filename);
            string content <- string(json_f);
            
            write "Fichier JSON lu: " + length(content) + " chars";
            
            // PARSER AVEC from_json UNIQUEMENT
            do parse_with_from_json(content);
            
        } catch {
            write "ERREUR lecture fichier JSON";
        }
    }
    
    action parse_with_from_json(string content) {
        write "\n5. PARSING AVEC from_json";

        try {
            unknown root <- from_json(content);

            // CAS 1 : LE FICHIER EST UN ARRAY
            try {
                list<unknown> root_list <- list<unknown>(root);
                write "Format détecté: tableau JSON";
                
                if length(root_list) = 0 {
                    write "ERREUR: tableau JSON vide"; 
                    return;
                }

                // Tester premier élément pour nouveau format
                unknown first <- root_list[0];
                try {
                    map<string, unknown> m <- map<string, unknown>(first);
                    if ("trip_to_stop_ids" in m.keys) and ("trip_to_departure_times" in m.keys) {
                        write "→ Nouveau format détecté (objet dans un array)";
                        do extract_and_cast_data(m);
                        return;
                    }
                } catch { /* pas un map direct */ }

                // SINON : ANCIEN FORMAT
                write "→ Clés 'trip_to_*' absentes : tentative ancien format (array d'objets)";
                do parse_old_format_array(root_list);
                return;

            } catch {
                // CAS 2 : OBJET DIRECT
                try {
                    map<string, unknown> obj <- map<string, unknown>(root);
                    if ("trip_to_stop_ids" in obj.keys) and ("trip_to_departure_times" in obj.keys) {
                        write "→ Nouveau format détecté (objet direct)";
                        do extract_and_cast_data(obj);
                        return;
                    }
                } catch { /* impossible de traiter comme objet */ }
            }

            write "❌ Format JSON non reconnu";

        } catch {
            write "ERREUR parsing JSON avec from_json";
        }
    }
    
    action extract_and_cast_data(map<string, unknown> parsed) {
        write "\n6. EXTRACTION ET CAST DES DONNÉES (NOUVEAU FORMAT)";
        
        try {
            // CAST PROPRE DES DEUX DICTIONNAIRES
            map<string, unknown> stops_u <- map<string, unknown>(parsed["trip_to_stop_ids"]);
            map<string, unknown> times_u <- map<string, unknown>(parsed["trip_to_departure_times"]);
            
            write "DEBUG: stops_u keys count: " + length(stops_u.keys);
            write "DEBUG: times_u keys count: " + length(times_u.keys);
            
            if empty(stops_u.keys) {
                write "ERREUR: Aucune clé trouvée dans trip_to_stop_ids";
                return;
            }
            
            // AFFICHER STRUCTURE INTERMÉDIAIRE
            write "\n=== STRUCTURE INTERMÉDIAIRE trip_to_stop_ids ===";
            write "Premiers tripIds trouvés :";
            loop i from: 0 to: min(4, length(stops_u.keys) - 1) {
                write "  " + stops_u.keys[i];
            }
            
            // INITIALISER LES MAPS FINALES
            trip_to_stop_ids <- map<string, list<string>>([]);
            trip_to_departure_times <- map<string, list<int>>([]);
            
            int processed_count <- 0;
            int aligned_count <- 0;
            
            loop trip over: stops_u.keys {
                processed_count <- processed_count + 1;
                
                if processed_count <= 3 {
                    write "DEBUG: Traitement trip " + trip;
                }
                
                try {
                    // EXTRAIRE STOPS
                    list<string> stops <- list<string>(stops_u[trip]);
                    
                    // EXTRAIRE ET CONVERTIR TIMES
                    list<unknown> raw_times <- list<unknown>(times_u[trip]);
                    list<int> times <- [];
                    
                    loop t over: raw_times {
                        int v <- 0;
                        try { 
                            v <- int(t); 
                        } catch {
                            v <- do_parse_time_to_sec(string(t));
                        }
                        if v > 0 { 
                            times <- times + v; 
                        }
                    }
                    
                    // VÉRIFIER ALIGNEMENT
                    if length(stops) = length(times) and length(stops) > 0 {
                        trip_to_stop_ids[trip] <- stops;
                        trip_to_departure_times[trip] <- times;
                        aligned_count <- aligned_count + 1;
                        
                        // LOG DES PREMIERS EXEMPLES AVEC DÉTAILS
                        if aligned_count <= 3 {
                            write "✓ " + trip + ": " + length(stops) + " stops/times alignés";
                            write "  Stops: ";
                            loop i from: 0 to: min(4, length(stops) - 1) {
                                write "    " + stops[i];
                            }
                            write "  Times: ";
                            loop i from: 0 to: min(4, length(times) - 1) {
                                write "    " + times[i];
                            }
                        }
                    } else {
                        if processed_count <= 5 {
                            write "✗ " + trip + ": désalignement (" + length(stops) + " stops, " + length(times) + " times)";
                        }
                    }
                    
                } catch {
                    if processed_count <= 5 {
                        write "ERREUR cast pour trip " + trip;
                    }
                }
            }
            
            write "\nStatistiques finales JSON:";
            write "Trips traités: " + processed_count;
            write "Trips alignés: " + aligned_count;
            
            if processed_count > 0 {
                float alignment_rate <- (aligned_count * 100.0) / processed_count;
                write "Taux d'alignement: " + alignment_rate + "%";
            } else {
                write "Taux d'alignement: 0% (aucun trip traité)";
            }
            
            // RECONSTRUIRE LES PAIRES AVEC AGENTS
            if aligned_count > 0 {
                do reconstruct_departure_pairs_with_agents;
                
                // NOUVELLE PHASE : LIAISON TRIP → ROUTE
                do build_trip_to_route_mapping;
                
                do show_json_examples;
            }
            
        } catch {
            write "ERREUR générale dans extract_and_cast_data";
        }
    }
    
    action parse_old_format_array(list<unknown> arr) {
        write "\n6. PARSING ANCIEN FORMAT (ARRAY D'OBJETS ARRÊT)";
        
        map<string, list<string>> stopIds <- map<string, list<string>>([]);
        map<string, list<int>> times <- map<string, list<int>>([]);
        
        int objects_processed <- 0;
        int trips_found <- 0;
        
        // HEURISTIQUE 2-OBJETS : Format { tripId → ... }
        if length(arr) = 2 {
            write "DEBUG: Détection format 2-objets (heuristique)";
            
            try {
                map<string, unknown> obj1 <- map<string, unknown>(arr[0]);
                map<string, unknown> obj2 <- map<string, unknown>(arr[1]);
                
                write "DEBUG: Obj1 a " + length(obj1.keys) + " clés";
                write "DEBUG: Obj2 a " + length(obj2.keys) + " clés";
                
                // Vérifier si les clés sont des tripIds (format XX_X_MD_X)
                bool obj1_has_tripids <- false;
                bool obj2_has_tripids <- false;
                
                if !empty(obj1.keys) {
                    string first_key1 <- obj1.keys[0];
                    if first_key1 contains "_MD_" {
                        obj1_has_tripids <- true;
                        write "DEBUG: Obj1 contient des tripIds (ex: " + first_key1 + ")";
                    }
                }
                
                if !empty(obj2.keys) {
                    string first_key2 <- obj2.keys[0];
                    if first_key2 contains "_MD_" {
                        obj2_has_tripids <- true;
                        write "DEBUG: Obj2 contient des tripIds (ex: " + first_key2 + ")";
                    }
                }
                
                if obj1_has_tripids and obj2_has_tripids {
                    write "→ Format 3ème type détecté : 2 dictionnaires { tripId → données }";
                    
                    // Tester obj1=stops, obj2=times
                    do parse_two_trip_dicts_robust(obj1, obj2, true);
                    
                    if !empty(trip_to_stop_ids) {
                        write "✅ Parsing réussi avec obj1=stops, obj2=times";
                        do reconstruct_departure_pairs_with_agents;
                        
                        // NOUVELLE PHASE : LIAISON TRIP → ROUTE (AJOUT MANQUANT)
                        do build_trip_to_route_mapping;
                        
                        do show_json_examples;
                        return;
                    }
                    
                    // Si échec, tester obj1=times, obj2=stops
                    write "DEBUG: Essai inverse obj1=times, obj2=stops";
                    do parse_two_trip_dicts_robust(obj2, obj1, true);
                    
                    if !empty(trip_to_stop_ids) {
                        write "✅ Parsing réussi avec obj1=times, obj2=stops";
                        do reconstruct_departure_pairs_with_agents;
                        
                        // NOUVELLE PHASE : LIAISON TRIP → ROUTE (AJOUT MANQUANT)
                        do build_trip_to_route_mapping;
                        
                        do show_json_examples;
                        return;
                    }
                    
                    write "❌ Format 3ème type : longueurs incompatibles";
                }
            } catch {
                write "ERREUR: Impossible de traiter comme format 2-objets";
            }
        }
        
        // FALLBACK : Format original avec departureStopsInfo
        write "DEBUG: Tentative format original avec departureStopsInfo";
        
        loop u over: arr {
            objects_processed <- objects_processed + 1;
            
            try {
                map<string, unknown> stopObj <- map<string, unknown>(u);
                
                if "departureStopsInfo" in stopObj.keys {
                    map<string, unknown> dep <- map<string, unknown>(stopObj["departureStopsInfo"]);
                    
                    loop tripId over: dep.keys {
                        if !(tripId in stopIds.keys) {
                            try {
                                list<unknown> pairs <- list<unknown>(dep[tripId]);
                                list<string> sids <- [];
                                list<int> tms <- [];
                                
                                loop p over: pairs {
                                    try {
                                        list<unknown> pr <- list<unknown>(p);
                                        if length(pr) >= 2 {
                                            string sid <- string(pr[0]);
                                            int t <- 0;
                                            
                                            try { 
                                                t <- int(pr[1]); 
                                            } catch { 
                                                t <- do_parse_time_to_sec(string(pr[1])); 
                                            }
                                            
                                            if sid != "" and t >= 0 { 
                                                sids <- sids + sid; 
                                                tms <- tms + t; 
                                            }
                                        }
                                    } catch {
                                        // Ignorer les paires malformées
                                    }
                                }
                                
                                if !empty(sids) and length(sids) = length(tms) {
                                    stopIds[tripId] <- sids;
                                    times[tripId] <- tms;
                                    trips_found <- trips_found + 1;
                                }
                            } catch {
                                // Ignorer les erreurs de parsing
                            }
                        }
                    }
                }
            } catch {
                // Ignorer les objets malformés
            }
        }
        
        write "\nStatistiques ancien format:";
        write "Objets traités: " + objects_processed;
        write "Trips extraits: " + trips_found;
        
        if trips_found > 0 {
            trip_to_stop_ids <- stopIds;
            trip_to_departure_times <- times;
            
            write "✅ Conversion réussie vers format interne";
            do reconstruct_departure_pairs_with_agents;
            
            // NOUVELLE PHASE : LIAISON TRIP → ROUTE (AJOUT MANQUANT)
            do build_trip_to_route_mapping;
            
            do show_json_examples;
        } else {
            write "❌ Aucun trip trouvé dans l'ancien format";
        }
    }
    
    action parse_two_trip_dicts_robust(map<string, unknown> stops_dict, map<string, unknown> times_dict, bool reset_maps) {
        write "DEBUG: Tentative parsing 2 dictionnaires { tripId → données }";
        if reset_maps {
            trip_to_stop_ids <- map<string, list<string>>([]);
            trip_to_departure_times <- map<string, list<int>>([]);
        }

        int processed_count <- 0;
        int aligned_count <- 0;
        int max_process <- 500; // Limité pour éviter timeouts

        // Clés communes
        list<string> common_trips <- [];
        loop trip over: stops_dict.keys { 
            if trip in times_dict.keys { 
                common_trips <- common_trips + trip; 
            } 
        }
        write "DEBUG: " + length(common_trips) + " trips communs trouvés";

        loop trip over: common_trips {
            processed_count <- processed_count + 1;
            try {
                // STOPS - PARSING ROBUSTE
                list<unknown> raw_stops <- try_to_list_robust(stops_dict[trip]);
                list<string> stops <- [];
                loop x over: raw_stops { 
                    try { 
                        string stop_id <- string(x);
                        if stop_id != "" and !(stop_id in ["[", "]", "'", "\"", ","]) {
                            stops <- stops + stop_id; 
                        }
                    } catch { }
                }

                // TIMES - PARSING ROBUSTE
                list<unknown> raw_times <- try_to_list_robust(times_dict[trip]);
                list<int> times <- [];
                loop t over: raw_times {
                    int v <- 0;
                    try { 
                        v <- int(t); 
                    } catch { 
                        string t_str <- string(t);
                        if t_str != "" and !(t_str in ["[", "]", "'", "\"", ","]) {
                            v <- do_parse_time_to_sec(t_str); 
                        }
                    }
                    if v > 0 { 
                        times <- times + v; 
                    }
                }

                // Alignement
                if length(stops) = length(times) and length(stops) > 0 {
                    trip_to_stop_ids[trip] <- stops;
                    trip_to_departure_times[trip] <- times;
                    aligned_count <- aligned_count + 1;
                }
            } catch {
                // Ignorer les erreurs de parsing
            }
            
            if processed_count >= max_process { 
                write "LIMITE ATTEINTE: " + max_process + " trips traités";
                break; 
            }
        }

        write "DEBUG: Trips traités=" + processed_count + ", alignés=" + aligned_count;
    }
    
    // FONCTION ROBUSTE POUR PARSER LES LISTES
    list<unknown> try_to_list_robust(unknown v) {
        try {
            list<unknown> direct <- list<unknown>(v);
            if !empty(direct) {
                string first_elem <- string(direct[0]);
                if length(first_elem) = 1 and (first_elem = "[" or first_elem = "'" or first_elem = "\"" or first_elem = "{") {
                    return parse_string_list_robust(string(v));
                } else {
                    return direct;
                }
            }
            return direct;
        } catch {
            return parse_string_list_robust(string(v));
        }
    }

    list<unknown> parse_string_list_robust(string s) {
        if s = nil or s = "" { return []; }
        
        string cleaned <- s replace("\n", "") replace("\r", "") replace("\t", "");
        
        try { 
            list<unknown> result <- list<unknown>(from_json(cleaned));
            return result;
        } catch { }
        
        string s2 <- cleaned replace ("'", "\"");
        try { 
            list<unknown> result <- list<unknown>(from_json(s2));
            return result;
        } catch { }
        
        if cleaned contains "[" and cleaned contains "]" {
            try {
                string content <- cleaned replace("[", "") replace("]", "");
                if content contains "," {
                    list<string> parts <- content split_with ",";
                    list<unknown> manual_result <- [];
                    loop part over: parts {
                        string trimmed <- part replace("'", "") replace("\"", "") replace(" ", "");
                        if trimmed != "" {
                            manual_result <- manual_result + trimmed;
                        }
                    }
                    if !empty(manual_result) {
                        return manual_result;
                    }
                }
            } catch { }
        }
        
        return [];
    }
    
    int do_parse_time_to_sec(string s) {
        if s = nil or s = "" { return 0; }
        
        try { 
            return int(s); 
        } catch {
            if s contains ":" {
                list<string> parts <- s split_with ":";
                if length(parts) >= 2 {
                    try {
                        int h <- int(parts[0]);
                        int m <- int(parts[1]);
                        int sec <- (length(parts) >= 3 ? int(parts[2]) : 0);
                        return 3600 * h + 60 * m + sec;
                    } catch { 
                        return 0; 
                    }
                }
            }
            try { 
                return int(float(s)); 
            } catch { 
                return 0; 
            }
        }
    }
    
    // ####################################
    // NOUVELLE SECTION : TRANSFORMATION VERS AGENTS (CORRIGÉE)
    // ####################################
    
    action reconstruct_departure_pairs_with_agents {
        write "\n7. RECONSTRUCTION PAIRES (agent_bus_stop, time)";
        
        trip_to_pairs <- map<string, list<pair<bus_stop,int>>>([]);
        int successful_conversions <- 0;
        int failed_conversions <- 0;
        int nil_agents_found <- 0;
        
        loop trip over: trip_to_stop_ids.keys {
            list<string> stops <- trip_to_stop_ids[trip];
            list<int> times <- trip_to_departure_times[trip];
            
            list<pair<bus_stop,int>> pairs <- [];
            
            loop i from: 0 to: (length(stops) - 1) {
                string stop_id <- stops[i];
                int time <- times[i];
                
                // APPROCHE SIMPLE : Toujours ajouter la paire d'abord
                if stop_id in stopId_to_agent.keys {
                    bus_stop stop_agent <- stopId_to_agent[stop_id];
                    pairs <- pairs + pair(stop_agent, time);
                    successful_conversions <- successful_conversions + 1;
                } else {
                    failed_conversions <- failed_conversions + 1;
                    if failed_conversions <= 10 {
                        write "⚠️ STOP_ID MANQUANT: " + stop_id;
                    }
                }
            }
            
            // POST-FILTRAGE : Nettoyer les agents NIL APRÈS création
            list<pair<bus_stop,int>> clean_pairs <- [];
            loop p over: pairs {
                bus_stop stop_agent <- p.key;
                int time <- p.value;
                
                // LOGIQUE CORRIGÉE : Ajouter directement les agents valides
                if stop_agent = nil {
                    nil_agents_found <- nil_agents_found + 1;
                    if nil_agents_found <= 5 {
                        write "🔴 AGENT RÉELLEMENT NIL détecté";
                    }
                    // Ne pas ajouter à clean_pairs
                } else {
                    clean_pairs <- clean_pairs + p;
                    
                    // Debug des premiers agents valides (limité pour éviter spam)
                    if length(clean_pairs) <= 3 and length(clean_pairs) mod 1 = 1 {
                        write "✅ AGENT VALIDE: " + stop_agent.stopId + " (type: " + string(type_of(stop_agent)) + ")";
                    }
                }
            }
            
            // Ne garder que les trips avec au moins une paire valide
            if !empty(clean_pairs) {
                trip_to_pairs[trip] <- clean_pairs;
            }
            
            // Debug pour le premier trip
            if trip = trip_to_stop_ids.keys[0] {
                write "DEBUG Premier trip: " + trip;
                write "  - Paires brutes: " + length(pairs);
                write "  - Paires nettoyées: " + length(clean_pairs);
                write "  - Agents nil trouvés: " + (length(pairs) - length(clean_pairs));
            }
        }
        
        write "Paires (agent_bus_stop, time) reconstituées :";
        write "  - Trips conservés : " + length(trip_to_pairs);
        write "  - Conversions réussies : " + successful_conversions;
        write "  - Conversions échouées : " + failed_conversions;
        
        // Statistiques corrigées : calculer le vrai nombre d'agents dans les résultats finaux
        int final_pairs_count <- 0;
        loop trip over: trip_to_pairs.keys {
            final_pairs_count <- final_pairs_count + length(trip_to_pairs[trip]);
        }
        
        write "  - Paires finales (agents valides) : " + final_pairs_count;
        
        if nil_agents_found > 0 {
            write "  - Agents NIL détectés et filtrés : " + nil_agents_found;
        }
        
        if (successful_conversions + failed_conversions) > 0 {
            float success_rate <- (successful_conversions * 100.0) / (successful_conversions + failed_conversions);
            write "  - Taux de succès : " + success_rate + "%";
        }
        
        if successful_conversions > 0 and nil_agents_found > 0 {
            float nil_rate <- (nil_agents_found * 100.0) / successful_conversions;
            write "  - Taux d'agents nil : " + nil_rate + "%";
        }
    }
    
    // ####################################
    // NOUVELLE SECTION : LIAISON TRIP → ROUTE
    // ####################################
    
    action build_trip_to_route_mapping {
        write "\n9. CONSTRUCTION LIAISON TRIP → ROUTE";
        
        tripId_to_main_route <- map<string, bus_route>([]);
        tripId_to_all_routes <- map<string, list<bus_route>>([]);
        tripId_to_route_frequencies <- map<string, map<string, int>>([]);
        
        int trips_processed <- 0;
        int trips_with_routes <- 0;
        int trips_multiple_routes <- 0;
        
        loop trip over: trip_to_pairs.keys {
            trips_processed <- trips_processed + 1;
            
            list<pair<bus_stop,int>> pairs <- trip_to_pairs[trip];
            map<string, int> route_frequency <- map<string, int>([]);
            list<bus_route> all_routes_for_trip <- [];
            
            // COMPTER FRÉQUENCE DES ROUTES POUR CE TRIP
            loop p over: pairs {
                bus_stop stop_agent <- p.key;
                if stop_agent != nil and stop_agent.is_matched and stop_agent.closest_route_id != nil and stop_agent.closest_route_id != "" {
                    string route_osm_id <- stop_agent.closest_route_id;
                    
                    // Incrémenter fréquence
                    route_frequency[route_osm_id] <- (route_frequency contains_key route_osm_id) ? 
                        route_frequency[route_osm_id] + 1 : 1;
                    
                    // Ajouter à la liste des routes (sans doublon)
                    if osmId_to_route contains_key route_osm_id {
                        bus_route route_agent <- osmId_to_route[route_osm_id];
                        if !(route_agent in all_routes_for_trip) {
                            all_routes_for_trip <- all_routes_for_trip + route_agent;
                        }
                    }
                }
            }
            
            // ANALYSER RÉSULTATS POUR CE TRIP
            if !empty(route_frequency.keys) {
                trips_with_routes <- trips_with_routes + 1;
                
                // Stocker les fréquences (pour debug)
                tripId_to_route_frequencies[trip] <- route_frequency;
                
                // Stocker toutes les routes
                if !empty(all_routes_for_trip) {
                    tripId_to_all_routes[trip] <- all_routes_for_trip;
                    
                    if length(all_routes_for_trip) > 1 {
                        trips_multiple_routes <- trips_multiple_routes + 1;
                    }
                }
                
                // TROUVER LA ROUTE PRINCIPALE (plus fréquente)
                string main_route_osm_id <- "";
                int max_frequency <- 0;
                
                loop route_id over: route_frequency.keys {
                    if route_frequency[route_id] > max_frequency {
                        max_frequency <- route_frequency[route_id];
                        main_route_osm_id <- route_id;
                    }
                }
                
                // ASSOCIER AU BUS_ROUTE AGENT
                if main_route_osm_id != "" and osmId_to_route contains_key main_route_osm_id {
                    bus_route main_route_agent <- osmId_to_route[main_route_osm_id];
                    tripId_to_main_route[trip] <- main_route_agent;
                    
                    // Debug des premiers cas
                    if trips_with_routes <= 5 {
                        write "✓ " + trip + " → Route: " + main_route_agent.osm_id + 
                              " (" + main_route_agent.route_name + ") [" + max_frequency + " arrêts]";
                        
                        if length(all_routes_for_trip) > 1 {
                            write "  Routes secondaires: ";
                            loop r over: all_routes_for_trip {
                                if r.osm_id != main_route_osm_id {
                                    int freq <- route_frequency contains_key r.osm_id ? route_frequency[r.osm_id] : 0;
                                    write "    " + r.osm_id + " (" + r.route_name + ") [" + freq + " arrêts]";
                                }
                            }
                        }
                    }
                }
            }
        }
        
        write "\nStatistiques liaison Trip → Route :";
        write "  - Trips traités : " + trips_processed;
        write "  - Trips avec routes : " + trips_with_routes;
        write "  - Trips multi-routes : " + trips_multiple_routes;
        write "  - Liaisons principales créées : " + length(tripId_to_main_route);
        
        if trips_processed > 0 {
            float route_coverage <- (trips_with_routes * 100.0) / trips_processed;
            write "  - Couverture routes : " + route_coverage + "%";
        }
        
        if trips_with_routes > 0 {
            float multi_route_rate <- (trips_multiple_routes * 100.0) / trips_with_routes;
            write "  - Taux multi-routes : " + multi_route_rate + "%";
        }
    }
    
    action show_json_examples {
        write "\n8. EXEMPLES DE DONNÉES JSON (avec agents)";
        
        if !empty(trip_to_pairs) {
            list<string> trip_ids <- trip_to_pairs.keys;
            
            // PREMIER EXEMPLE
            string example_trip <- trip_ids[0];
            list<pair<bus_stop,int>> example_pairs <- trip_to_pairs[example_trip];
            
            write "\nExemple 1 - Trip: " + example_trip;
            write "  Nombre de paires (agent, time): " + length(example_pairs);
            
            write "  Premières paires: ";
            loop i from: 0 to: min(2, length(example_pairs) - 1) {
                pair<bus_stop,int> p <- example_pairs[i];
                bus_stop stop_agent <- p.key;
                int time <- p.value;
                
                // CORRECTION DU CODE MALFORMÉ
                if stop_agent != nil {
                    write "    Agent: " + stop_agent.stopId + " (" + stop_agent.stop_name + "), Time: " + time;
                    write "      Position: " + stop_agent.location;
                    write "      Matché: " + (stop_agent.is_matched ? "✓" : "✗");
                } else {
                    write "    Agent: NIL, Time: " + time;
                }
            }
            
            // STATISTIQUES FINALES
            write "\n=== STATISTIQUES GÉNÉRALES JSON (avec agents) ===";
            write "Total trips avec agents: " + length(trip_to_pairs);
            
            int total_agent_pairs <- 0;
            loop trip over: trip_to_pairs.keys {
                total_agent_pairs <- total_agent_pairs + length(trip_to_pairs[trip]);
            }
            write "Total paires (agent, time): " + total_agent_pairs;
            
            if !empty(trip_to_pairs) {
                float avg_pairs <- total_agent_pairs / length(trip_to_pairs);
                write "Moyenne paires par trip: " + avg_pairs;
            }
        }
    }
    
    // ####################################
    // APIS D'ACCÈS COMBINÉES (MODIFIÉES)
    // ####################################
    
    // APIS RÉSEAU (inchangées)
    bus_stop get_stop_agent(string stop_id) {
        if stopId_to_agent contains_key stop_id {
            return stopId_to_agent[stop_id];
        }
        return nil;
    }
    
    bus_route get_route_by_osm_id(string osm_id) {
        if osmId_to_route contains_key osm_id {
            return osmId_to_route[osm_id];
        }
        return nil;
    }
    
    list<bus_stop> get_matched_stops {
        return list<bus_stop>(bus_stop where (each.is_matched));
    }
    
    list<bus_stop> get_unmatched_stops {
        return list<bus_stop>(bus_stop where (!each.is_matched));
    }
    
    list<string> get_all_stop_ids {
        return stopId_to_agent.keys;
    }
    
    list<string> get_all_route_osm_ids {
        return osmId_to_route.keys;
    }
    
    // APIS JSON ORIGINALES (pour stopId)
    list<string> get_trip_stops(string trip_id) {
        if trip_to_stop_ids contains_key trip_id {
            return trip_to_stop_ids[trip_id];
        }
        return [];
    }
    
    list<int> get_trip_times(string trip_id) {
        if trip_to_departure_times contains_key trip_id {
            return trip_to_departure_times[trip_id];
        }
        return list<int>([]);
    }
    
    // NOUVELLES APIS POUR AGENTS
    list<pair<bus_stop,int>> get_trip_pairs(string trip_id) {
        if trip_to_pairs contains_key trip_id {
            return trip_to_pairs[trip_id];
        }
        return [];
    }
    
    list<bus_stop> get_trip_agents(string trip_id) {
        if trip_to_pairs contains_key trip_id {
            list<pair<bus_stop,int>> pairs <- trip_to_pairs[trip_id];
            list<bus_stop> agents <- [];
            loop p over: pairs {
                agents <- agents + p.key;
            }
            return agents;
        }
        return [];
    }
    
    list<int> get_trip_times_for_agents(string trip_id) {
        if trip_to_pairs contains_key trip_id {
            list<pair<bus_stop,int>> pairs <- trip_to_pairs[trip_id];
            list<int> times <- [];
            loop p over: pairs {
                times <- times + p.value;
            }
            return times;
        }
        return list<int>([]);
    }
    
    list<pair<bus_stop,int>> get_trip_pairs_filtered(string trip_id, bool only_matched_stops) {
        list<pair<bus_stop,int>> agent_pairs <- get_trip_pairs(trip_id);
        
        if only_matched_stops {
            list<pair<bus_stop,int>> filtered_pairs <- [];
            loop p over: agent_pairs {
                bus_stop stop_agent <- p.key;
                if stop_agent != nil and stop_agent.is_matched {
                    filtered_pairs <- filtered_pairs + p;
                }
            }
            return filtered_pairs;
        }
        
        return agent_pairs;
    }
    
    list<string> get_all_trip_ids {
        return trip_to_pairs.keys;
    }
    
    // UTILITAIRES
    int get_total_trips {
        return length(trip_to_pairs);
    }
    
    int get_total_agent_pairs {
        int total <- 0;
        loop trip over: trip_to_pairs.keys {
            total <- total + length(trip_to_pairs[trip]);
        }
        return total;
    }
    
    // ####################################
    // NOUVELLES APIS POUR LIAISON TRIP → ROUTE
    // ####################################
    
    // Obtenir la route principale d'un trip
    bus_route get_trip_main_route(string trip_id) {
        if tripId_to_main_route contains_key trip_id {
            return tripId_to_main_route[trip_id];
        }
        return nil;
    }
    
    // Obtenir toutes les routes d'un trip
    list<bus_route> get_trip_all_routes(string trip_id) {
        if tripId_to_all_routes contains_key trip_id {
            return tripId_to_all_routes[trip_id];
        }
        return [];
    }
    
    // Obtenir les fréquences des routes pour un trip (debug/analyse)
    map<string, int> get_trip_route_frequencies(string trip_id) {
        if tripId_to_route_frequencies contains_key trip_id {
            return tripId_to_route_frequencies[trip_id];
        }
        return map<string, int>([]);
    }
    
    // Obtenir tous les trips utilisant une route spécifique
    list<string> get_trips_using_route(string route_osm_id) {
        list<string> trips <- [];
        loop trip over: tripId_to_main_route.keys {
            bus_route route <- tripId_to_main_route[trip];
            if route != nil and route.osm_id = route_osm_id {
                trips <- trips + trip;
            }
        }
        return trips;
    }
    
    // Obtenir tous les trips utilisant une route (agent)
    list<string> get_trips_using_route_agent(bus_route route_agent) {
        list<string> trips <- [];
        if route_agent != nil {
            loop trip over: tripId_to_main_route.keys {
                bus_route trip_route <- tripId_to_main_route[trip];
                if trip_route != nil and trip_route = route_agent {
                    trips <- trips + trip;
                }
            }
        }
        return trips;
    }
    
    // Statistiques générales des liaisons
    int get_total_trip_route_mappings {
        return length(tripId_to_main_route);
    }
    
    int get_trips_with_multiple_routes {
        int count <- 0;
        loop trip over: tripId_to_all_routes.keys {
            if length(tripId_to_all_routes[trip]) > 1 {
                count <- count + 1;
            }
        }
        return count;
    }
    
    // Obtenir les routes les plus utilisées
    map<string, int> get_route_usage_statistics {
        map<string, int> route_usage <- map<string, int>([]);
        
        loop trip over: tripId_to_main_route.keys {
            bus_route route <- tripId_to_main_route[trip];
            if route != nil {
                string route_key <- route.osm_id + " (" + route.route_name + ")";
                route_usage[route_key] <- (route_usage contains_key route_key) ? 
                    route_usage[route_key] + 1 : 1;
            }
        }
        
        return route_usage;
    }
}

// ####################################
// AGENTS (INCHANGÉS)
// ####################################

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
    
    aspect detailed {
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
            draw shape color: route_color width: 3;
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
        rgb stop_color <- is_matched ? #green : #red;
        draw circle(100.0) color: stop_color;
    }
    
    aspect detailed {
        rgb stop_color <- is_matched ? #green : #red;
        draw circle(120.0) color: stop_color;
        
        if is_matched {
            draw circle(160.0) border: #darkgreen width: 2;
        }
        
        if stopId != nil and stopId != "" {
            draw stopId at: location + {0, -200} color: #gray size: 8;
        }
        
        if is_matched and closest_route_dist > 0 {
            draw string(int(closest_route_dist)) + "m" at: location + {0, 220} color: #blue size: 8;
        }
    }
    
    aspect minimal {
        rgb stop_color <- is_matched ? #green : #red;
        draw circle(80.0) color: stop_color;
    }
}

// ####################################
// EXPERIMENT COMBINÉ (MODIFIÉ)
// ####################################

experiment combined_network_json type: gui {
    
    action reload_all {
        ask world {
            // Nettoyer agents
            ask bus_route { do die; }
            ask bus_stop { do die; }
            
            // Reset variables réseau
            total_bus_routes <- 0;
            total_bus_stops <- 0;
            matched_stops <- 0;
            unmatched_stops <- 0;
            stopId_to_agent <- map<string, bus_stop>([]);
            osmId_to_route <- map<string, bus_route>([]);
            
            // Reset variables JSON
            trip_to_stop_ids <- map<string, list<string>>([]);
            trip_to_departure_times <- map<string, list<int>>([]);
            trip_to_pairs <- map<string, list<pair<bus_stop,int>>>([]);
            
            // Reset nouvelles variables Trip → Route
            tripId_to_main_route <- map<string, bus_route>([]);
            tripId_to_all_routes <- map<string, list<bus_route>>([]);
            tripId_to_route_frequencies <- map<string, map<string, int>>([]);
            
            // Recharger tout
            write "\n=== RECHARGEMENT COMPLET ===";
            
            write "\n▶ PHASE 1 : CHARGEMENT RÉSEAU BUS";
            do load_bus_network;
            do load_gtfs_stops;
            do build_basic_mappings;
            do display_network_statistics;
            
            write "\n▶ PHASE 2 : PARSING DONNÉES JSON";
            do load_json_robust;
            
            write "\n=== RECHARGEMENT TERMINÉ ===";
        }
    }
    
    user_command "Recharger Tout" action: reload_all;
    
    output {
        display "Réseau Bus + Données JSON" background: #white type: 2d {
            species bus_route aspect: default;
            species bus_stop aspect: default;
            
            overlay position: {10, 10} size: {300 #px, 180 #px} background: #white transparency: 0.9 border: #black {
                draw "=== MODÈLE COMBINÉ ===" at: {10#px, 20#px} color: #black font: font("Arial", 10, #bold);
                draw "Routes: " + total_bus_routes at: {10#px, 40#px} color: #blue;
                draw "Arrêts: " + total_bus_stops at: {10#px, 60#px} color: #green;
                draw "Trips JSON: " + length(trip_to_pairs) at: {10#px, 80#px} color: #purple;
                draw "Paires agents: " + get_total_agent_pairs() at: {10#px, 100#px} color: #orange;
                draw "Liaisons Trip→Route: " + get_total_trip_route_mappings() at: {10#px, 120#px} color: #red;
                draw "Multi-routes: " + get_trips_with_multiple_routes() at: {10#px, 140#px} color: #darkred;
                draw "Voir console pour détails" at: {10#px, 160#px} color: #gray;
            }
        }
    }
}