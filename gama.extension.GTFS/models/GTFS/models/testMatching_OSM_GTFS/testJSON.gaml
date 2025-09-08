/**
 * PARSER JSON ROBUSTE - Version fonctionnelle finale
 */

model RobustJsonParser

global {
    string stops_folder <- "../../results/stopReseau/";
    map<string, list<string>> trip_to_stop_ids;
    map<string, list<int>> trip_to_departure_times;
    map<string, list<pair<string,int>>> trip_to_pairs;
    
    init {
        write "=== PARSER JSON ROBUSTE - VERSION FONCTIONNELLE ===";
        do load_json_robust;
    }
    
    action load_json_robust {
        write "\n1. LECTURE ET PARSING JSON";
        
        string json_filename <- stops_folder + "departure_stops_separated.json";
        
        try {
            file json_f <- text_file(json_filename);
            string content <- string(json_f);
            
            write "Fichier lu: " + length(content) + " chars";
            
            // PARSER AVEC from_json UNIQUEMENT
            do parse_with_from_json(content);
            
        } catch {
            write "ERREUR lecture fichier";
        }
    }
    
    action parse_with_from_json(string content) {
        write "\n2. PARSING AVEC from_json";

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

            write "❌ Format non reconnu";

        } catch {
            write "ERREUR parsing JSON avec from_json";
        }
    }
    
    action extract_and_cast_data(map<string, unknown> parsed) {
        write "\n3. EXTRACTION ET CAST DES DONNÉES (NOUVEAU FORMAT)";
        
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
            
            write "\nStatistiques finales:";
            write "Trips traités: " + processed_count;
            write "Trips alignés: " + aligned_count;
            
            if processed_count > 0 {
                float alignment_rate <- (aligned_count * 100.0) / processed_count;
                write "Taux d'alignement: " + alignment_rate + "%";
            } else {
                write "Taux d'alignement: 0% (aucun trip traité)";
            }
            
            // RECONSTRUIRE LES PAIRES SI NÉCESSAIRE
            if aligned_count > 0 {
                do reconstruct_departure_pairs;
                do show_examples;
            }
            
        } catch {
            write "ERREUR générale dans extract_and_cast_data";
        }
    }
    
    action parse_old_format_array(list<unknown> arr) {
        write "\n3. PARSING ANCIEN FORMAT (ARRAY D'OBJETS ARRÊT)";
        
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
                
                // AFFICHAGE DES STRUCTURES INTERMÉDIAIRES
                write "\n=== STRUCTURE INTERMÉDIAIRE OBJ1 ===";
                write "Premiers tripIds dans obj1:";
                loop i from: 0 to: min(4, length(obj1.keys) - 1) {
                    write "  " + obj1.keys[i];
                }
                
                write "\n=== STRUCTURE INTERMÉDIAIRE OBJ2 ===";
                write "Premiers tripIds dans obj2:";
                loop i from: 0 to: min(4, length(obj2.keys) - 1) {
                    write "  " + obj2.keys[i];
                }
                
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
                    
                    // DEBUG : Examiner le contenu d'un trip exemple
                    if !empty(obj1.keys) {
                        string sample_trip <- obj1.keys[0];
                        write "\n=== DEBUG CONTENU TRIP " + sample_trip + " ===";
                        
                        try {
                            list<unknown> sample1 <- try_to_list_robust(obj1[sample_trip]);
                            list<unknown> sample2 <- try_to_list_robust(obj2[sample_trip]);
                            
                            write "Obj1[" + sample_trip + "] : " + length(sample1) + " éléments (après parsing robuste)";
                            if length(sample1) > 0 {
                                write "  Premiers éléments: ";
                                loop idx from: 0 to: min(4, length(sample1) - 1) {
                                    write "    [" + idx + "]: " + string(sample1[idx]);
                                }
                                
                                // Tester le type du premier élément
                                string type1 <- "unknown";
                                try {
                                    int test_int <- int(sample1[0]);
                                    type1 <- "int";
                                } catch {
                                    try {
                                        string test_str <- string(sample1[0]);
                                        type1 <- "string";
                                    } catch {
                                        type1 <- "other";
                                    }
                                }
                                write "  Type détecté: " + type1;
                            } else {
                                write "  Liste vide après parsing";
                            }
                            
                            write "Obj2[" + sample_trip + "] : " + length(sample2) + " éléments (après parsing robuste)";
                            if length(sample2) > 0 {
                                write "  Premiers éléments: ";
                                loop idx from: 0 to: min(4, length(sample2) - 1) {
                                    write "    [" + idx + "]: " + string(sample2[idx]);
                                }
                                
                                // Tester le type du premier élément
                                string type2 <- "unknown";
                                try {
                                    int test_int <- int(sample2[0]);
                                    type2 <- "int";
                                } catch {
                                    try {
                                        string test_str <- string(sample2[0]);
                                        type2 <- "string";
                                    } catch {
                                        type2 <- "other";
                                    }
                                }
                                write "  Type détecté: " + type2;
                            } else {
                                write "  Liste vide après parsing";
                            }
                        } catch {
                            write "ERREUR lors de l'échantillonnage de " + sample_trip;
                        }
                    }
                    
                    // Tester obj1=stops, obj2=times
                    do parse_two_trip_dicts_robust(obj1, obj2, true);
                    
                    if !empty(trip_to_stop_ids) {
                        write "✅ Parsing réussi avec obj1=stops, obj2=times";
                        do reconstruct_departure_pairs;
                        do show_examples;
                        return;
                    }
                    
                    // Si échec, tester obj1=times, obj2=stops
                    write "DEBUG: Essai inverse obj1=times, obj2=stops";
                    do parse_two_trip_dicts_robust(obj2, obj1, true);
                    
                    if !empty(trip_to_stop_ids) {
                        write "✅ Parsing réussi avec obj1=times, obj2=stops";
                        do reconstruct_departure_pairs;
                        do show_examples;
                        return;
                    }
                    
                    write "❌ Format 3ème type : longueurs incompatibles (pas arrêts ↔ horaires)";
                    write "→ Recommandation : Régénérer le JSON avec trip_to_stop_ids et trip_to_departure_times alignés";
                }
            } catch {
                write "ERREUR: Impossible de traiter comme format 2-objets";
            }
        }
        
        // FALLBACK : Format original avec departureStopsInfo
        write "DEBUG: Tentative format original avec departureStopsInfo";
        
        loop u over: arr {
            objects_processed <- objects_processed + 1;
            
            if objects_processed <= 3 {
                write "DEBUG: Objet " + objects_processed;
            }
            
            // si l'élément est une chaîne JSON, reparse-le d'abord
            try {
                string s <- string(u);
                if objects_processed <= 2 {
                    write "DEBUG: Objet " + objects_processed + " est une string, re-parsing...";
                }
                unknown reparsed <- from_json(s);
                u <- reparsed;
            } catch { 
                if objects_processed <= 2 {
                    write "DEBUG: Objet " + objects_processed + " n'est pas une string JSON";
                }
            }
            
            try {
                map<string, unknown> stopObj <- map<string, unknown>(u);
                
                if objects_processed <= 2 {
                    write "DEBUG: Clés de l'objet " + objects_processed + ": ";
                    loop idx from: 0 to: min(9, length(stopObj.keys) - 1) {
                        write "    " + stopObj.keys[idx];
                    }
                }
                
                if "departureStopsInfo" in stopObj.keys {
                    map<string, unknown> dep <- map<string, unknown>(stopObj["departureStopsInfo"]);
                    
                    if objects_processed <= 2 {
                        write "DEBUG: departureStopsInfo trouvé avec " + length(dep.keys) + " trips";
                        write "DEBUG: Premiers trip IDs: ";
                        loop idx from: 0 to: min(2, length(dep.keys) - 1) {
                            write "    " + dep.keys[idx];
                        }
                    }
                    
                    loop tripId over: dep.keys {
                        // NE CRÉER QU'UNE FOIS PAR TRIP
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
                                    
                                    if trips_found <= 3 {
                                        write "✓ Trip " + tripId + ": " + length(sids) + " stops/times";
                                    }
                                }
                            } catch {
                                if trips_found <= 5 {
                                    write "✗ Erreur parsing trip " + tripId;
                                }
                            }
                        }
                    }
                } else {
                    if objects_processed <= 3 {
                        write "DEBUG: Objet " + objects_processed + " n'a pas 'departureStopsInfo'";
                    }
                }
            } catch {
                if objects_processed <= 5 {
                    write "✗ Erreur parsing objet " + objects_processed;
                }
            }
        }
        
        write "\nStatistiques ancien format:";
        write "Objets traités: " + objects_processed;
        write "Trips extraits: " + trips_found;
        
        if trips_found > 0 {
            // ASSIGNER AUX STRUCTURES FINALES
            trip_to_stop_ids <- stopIds;
            trip_to_departure_times <- times;
            
            write "✅ Conversion réussie vers format interne";
            
            // RECONSTRUIRE LES PAIRES
            do reconstruct_departure_pairs;
            do show_examples;
        } else {
            write "❌ Aucun trip trouvé dans l'ancien format";
        }
    }
    
    // VERSION ROBUSTE CORRIGÉE
    action parse_two_trip_dicts_robust(map<string, unknown> stops_dict, map<string, unknown> times_dict, bool reset_maps) {
        write "DEBUG: Tentative parsing 2 dictionnaires { tripId → données } - VERSION ROBUSTE";
        if reset_maps {
            trip_to_stop_ids <- map<string, list<string>>([]);
            trip_to_departure_times <- map<string, list<int>>([]);
        }

        int processed_count <- 0;
        int aligned_count <- 0;
        int max_process <- 1000; // AUGMENTÉ POUR TRAITER PLUS DE TRIPS

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
                    if aligned_count <= 3 { 
                        write "✓ " + trip + ": " + length(stops) + " stops/times alignés"; 
                    }
                } else {
                    if processed_count <= 5 { 
                        write "✗ " + trip + ": désalignement (" + length(stops) + " stops, " + length(times) + " times)"; 
                    }
                }
            } catch {
                if processed_count <= 5 { 
                    write "✗ Erreur cast/parse pour trip " + trip; 
                }
            }
            
            // Affichage périodique du progrès
            if processed_count mod 500 = 0 {
                write "Progrès: " + processed_count + "/" + length(common_trips) + " trips traités";
            }
            
            if processed_count >= max_process { 
                write "LIMITE ATTEINTE: " + max_process + " trips traités";
                break; 
            }
        }

        write "DEBUG: Trips traités=" + processed_count + ", alignés=" + aligned_count;
        if processed_count > 0 {
            float success_rate <- (aligned_count * 100.0) / processed_count;
            write "Taux de succès: " + success_rate + "%";
        }
    }
    
    // FONCTION ROBUSTE POUR PARSER LES LISTES
    list<unknown> try_to_list_robust(unknown v) {
        // 1) Tenter direct d'abord
        try {
            list<unknown> direct <- list<unknown>(v);
            // Si la liste n'est pas vide et ne semble pas être du parsing caractère par caractère
            if !empty(direct) {
                string first_elem <- string(direct[0]);
                // Si le premier élément est une seule lettre/caractère suspect, c'est probablement du parsing caractère
                if length(first_elem) = 1 and (first_elem = "[" or first_elem = "'" or first_elem = "\"" or first_elem = "{") {
                    write "DEBUG: Liste parsée caractère par caractère détectée, re-parsing...";
                    return parse_string_list_robust(string(v));
                } else {
                    return direct;
                }
            }
            return direct;
        } catch {
            // 2) Sinon, tenter via chaîne
            return parse_string_list_robust(string(v));
        }
    }

    list<unknown> parse_string_list_robust(string s) {
        if s = nil or s = "" { return []; }
        
        // a) Nettoyer la chaîne des caractères d'espacement excessifs
        string cleaned <- s replace("\n", "") replace("\r", "") replace("\t", "");
        
        // b) Tenter JSON strict
        try { 
            list<unknown> result <- list<unknown>(from_json(cleaned));
            write "DEBUG: Parsing JSON strict réussi, " + length(result) + " éléments";
            return result;
        } catch { 
            write "DEBUG: Parsing JSON strict échoué";
        }
        
        // c) Tenter normalisation quotes simples → doubles
        string s2 <- cleaned replace ("'", "\"");
        try { 
            list<unknown> result <- list<unknown>(from_json(s2));
            write "DEBUG: Parsing avec quotes doubles réussi, " + length(result) + " éléments";
            return result;
        } catch { 
            write "DEBUG: Parsing avec quotes doubles échoué";
        }
        
        // d) Parsing manuel basique pour les cas simples
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
                        write "DEBUG: Parsing manuel réussi, " + length(manual_result) + " éléments";
                        return manual_result;
                    }
                }
            } catch {
                write "DEBUG: Parsing manuel échoué";
            }
        }
        
        // e) échec total
        string debug_text <- s;
        if length(s) > 100 {
            debug_text <- copy_between(s, 0, 99) + "...";
        }
        write "DEBUG: Tous les parsings ont échoué pour: " + debug_text;
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
    
    action reconstruct_departure_pairs {
        write "\n4. RECONSTRUCTION PAIRES (stop,time)";
        
        trip_to_pairs <- map<string, list<pair<string,int>>>([]);
        
        loop trip over: trip_to_stop_ids.keys {
            list<string> stops <- trip_to_stop_ids[trip];
            list<int> times <- trip_to_departure_times[trip];
            
            list<pair<string,int>> pairs <- [];
            loop i from: 0 to: (length(stops) - 1) {
                pairs <- pairs + pair(stops[i], times[i]);
            }
            
            trip_to_pairs[trip] <- pairs;
        }
        
        write "Paires (stop,time) reconstituées pour " + length(trip_to_pairs) + " trips";
    }
    
    action show_examples {
        write "\n5. EXEMPLES DE DONNÉES";
        
        if !empty(trip_to_stop_ids) {
            list<string> trip_ids <- trip_to_stop_ids.keys;
            
            // PREMIER EXEMPLE
            string example_trip <- trip_ids[0];
            list<string> example_stops <- trip_to_stop_ids[example_trip];
            list<int> example_times <- trip_to_departure_times[example_trip];
            
            write "\nExemple 1 - Trip: " + example_trip;
            write "  Nombre d'arrêts: " + length(example_stops);
            write "  Premiers stops: ";
            loop idx from: 0 to: min(4, length(example_stops) - 1) {
                write "    " + example_stops[idx];
            }
            write "  Premiers times: ";
            loop idx from: 0 to: min(4, length(example_times) - 1) {
                write "    " + example_times[idx];
            }
            
            if example_trip in trip_to_pairs.keys {
                list<pair<string,int>> example_pairs <- trip_to_pairs[example_trip];
                write "  Premières paires (CORRIGÉES): ";
                loop i from: 0 to: min(2, length(example_pairs) - 1) {
                    pair<string,int> p <- example_pairs[i];
                    write "    (" + p.key + ", " + p.value + ")";
                }
            }
            
            // DEUXIÈME EXEMPLE SI DISPONIBLE
            if length(trip_ids) > 1 {
                string example2_trip <- trip_ids[1];
                list<string> example2_stops <- trip_to_stop_ids[example2_trip];
                list<int> example2_times <- trip_to_departure_times[example2_trip];
                
                write "\nExemple 2 - Trip: " + example2_trip;
                write "  Nombre d'arrêts: " + length(example2_stops);
                write "  Premiers stops: ";
                loop idx from: 0 to: min(2, length(example2_stops) - 1) {
                    write "    " + example2_stops[idx];
                }
                write "  Premiers times: ";
                loop idx from: 0 to: min(2, length(example2_times) - 1) {
                    write "    " + example2_times[idx];
                }
            }
            
            // STATISTIQUES FINALES
            write "\n=== STATISTIQUES GÉNÉRALES ===";
            write "Total trips chargés: " + length(trip_to_stop_ids);
            if !empty(trip_to_stop_ids) {
                int total_stops <- 0;
                loop trip over: trip_to_stop_ids.keys {
                    total_stops <- total_stops + length(trip_to_stop_ids[trip]);
                }
                float avg_stops <- total_stops / length(trip_to_stop_ids);
                write "Total arrêts: " + total_stops;
                write "Moyenne arrêts par trip: " + avg_stops;
            }
        }
    }
}

experiment robust_parser_test type: gui {
    output {
        display "Parser Robuste Fonctionnel" background: #white type: 2d {
            overlay position: {10, 10} size: {520 #px, 200 #px} background: #white transparency: 0.9 border: #black {
                draw "=== PARSER ROBUSTE FONCTIONNEL ===" at: {10#px, 20#px} color: #black font: font("Arial", 12, #bold);
                draw "✓ Affichage structures intermédiaires" at: {10#px, 40#px} color: #green;
                draw "✓ TripIds, stops et times détaillés" at: {10#px, 60#px} color: #green;
                draw "✓ Parsing robuste des listes" at: {10#px, 80#px} color: #green;
                draw "✓ 1000 trips maximum traités" at: {10#px, 100#px} color: #green;
                draw "✓ Paires (stop,time) correctes" at: {10#px, 120#px} color: #green;
                draw "✓ Statistiques complètes" at: {10#px, 140#px} color: #green;
                draw "✓ Progrès affiché tous les 500 trips" at: {10#px, 160#px} color: #green;
                draw "Voir console pour détails complets" at: {10#px, 180#px} color: #blue;
            }
        }
    }
}