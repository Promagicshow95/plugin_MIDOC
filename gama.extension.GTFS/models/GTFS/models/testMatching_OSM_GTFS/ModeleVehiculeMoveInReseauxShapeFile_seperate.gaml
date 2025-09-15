/**
 * PARSER JSON ROBUSTE - Recommandations appliquées
 */

model RobustJsonParser

global {
    string stops_folder <- "../../results/stopReseau/";
    map<string, list<string>> trip_to_stop_ids;
    map<string, list<int>> trip_to_departure_times;
    map<string, list<pair<string,int>>> trip_to_pairs;
    
    init {
        write "=== PARSER JSON ROBUSTE ===";
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
    
    action verify_json_structure(map<string, unknown> parsed) {
    write "\n3. VÉRIFICATION STRUCTURE";
    bool has_stops <- "trip_to_stop_ids" in parsed.keys;
    bool has_times <- "trip_to_departure_times" in parsed.keys;
    write "Clé 'trip_to_stop_ids': " + has_stops;
    write "Clé 'trip_to_departure_times': " + has_times;

    if !(has_stops and has_times) {
        write "❌ Structure JSON manquante (nouveau format non détecté)";
    } else {
        // Petites stats utiles
        map<string, unknown> stops_dict <- map<string, unknown>(parsed["trip_to_stop_ids"]);
        map<string, unknown> times_dict <- map<string, unknown>(parsed["trip_to_departure_times"]);
        write "Nombre de trips (stops): " + length(stops_dict);
        write "Nombre de trips (times): " + length(times_dict);
    }
}
    
    action parse_with_from_json(string content) {
    write "\n2. PARSING AVEC from_json";
    try {
        unknown root <- from_json(content);

        // --- CAS 1 : le root est un ARRAY ---
        try {
            list<unknown> root_list <- list<unknown>(root);
            write "Format détecté: tableau JSON";
            if length(root_list) = 0 { write "ERREUR: tableau JSON vide"; return; }

            unknown first <- root_list[0];
            bool handled <- false;

            // 1.a) Essayer "nouveau format" si le 1er élément est un objet avec les bonnes clés
            try {
                map<string, unknown> m <- map<string, unknown>(first);
                bool has_stops <- "trip_to_stop_ids" in m.keys;
                bool has_times <- "trip_to_departure_times" in m.keys;
                if has_stops and has_times {
                    write "→ Nouveau format détecté (objet dans un array)";
                    do extract_and_cast_data(m);
                    handled <- true;
                }
            } catch { /* pas un map : on verra l'ancien format */ }

            // 1.b) Sinon, tenter l'ANCIEN format: array d'objets arrêt
            if !handled {
                write "→ Clés 'trip_to_*' absentes : tentative ancien format (array d'objets arrêt)";
                do parse_old_format_array(root_list);
            }
            return;
        } catch { /* root n'est pas une liste */ }

        // --- CAS 2 : le root est un OBJET ---
        try {
            map<string, unknown> obj <- map<string, unknown>(root);
            bool has_stops <- "trip_to_stop_ids" in obj.keys;
            bool has_times <- "trip_to_departure_times" in obj.keys;

            if has_stops and has_times {
                write "→ Nouveau format détecté (objet direct)";
                do extract_and_cast_data(obj);
            } else {
                write "❌ Objet JSON sans 'trip_to_*' : ni nouveau format ni ancien format reconnus";
            }
            return;
        } catch {
            write "❌ Format non reconnu (ni array, ni objet JSON)";
        }
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
                        
                        // LOG DES PREMIERS EXEMPLES
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
        write "\n5. RECONSTRUCTION PAIRES (stop,time)";
        
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
        write "\n6. EXEMPLES DE DONNÉES";
        
        if !empty(trip_to_stop_ids) {
            list<string> trip_ids <- trip_to_stop_ids.keys;
            
            // PREMIER EXEMPLE
            string example_trip <- trip_ids[0];
            list<string> example_stops <- trip_to_stop_ids[example_trip];
            list<int> example_times <- trip_to_departure_times[example_trip];
            
            write "\nExemple 1 - Trip: " + example_trip;
            write "  Nombre d'arrêts: " + length(example_stops);
            write "  Premiers stops: " + copy_list(example_stops, 0, min(5, length(example_stops)));
            write "  Premiers times: " + copy_list(example_times, 0, min(5, length(example_times)));
            
            if example_trip in trip_to_pairs.keys {
                list<pair<string,int>> example_pairs <- trip_to_pairs[example_trip];
                write "  Premières paires: " + copy_list(example_pairs, 0, min(3, length(example_pairs)));
            }
            
            // DEUXIÈME EXEMPLE SI DISPONIBLE
            if length(trip_ids) > 1 {
                string example2_trip <- trip_ids[1];
                list<string> example2_stops <- trip_to_stop_ids[example2_trip];
                list<int> example2_times <- trip_to_departure_times[example2_trip];
                
                write "\nExemple 2 - Trip: " + example2_trip;
                write "  Nombre d'arrêts: " + length(example2_stops);
                write "  Premiers stops: " + copy_list(example2_stops, 0, min(3, length(example2_stops)));
                write "  Premiers times: " + copy_list(example2_times, 0, min(3, length(example2_times)));
            }
        }
    }
    
    list<unknown> copy_list(list<unknown> source, int start, int count) {
        list<unknown> result <- [];
        loop i from: start to: min(start + count - 1, length(source) - 1) {
            result <- result + source[i];
        }
        return result;
    }
    
    action parse_old_format_array(list<unknown> arr) {
        write "\n3. PARSING ANCIEN FORMAT (ARRAY D'OBJETS ARRÊT)";
        
        map<string, list<string>> stopIds <- map<string, list<string>>([]);
        map<string, list<int>> times <- map<string, list<int>>([]);
        
        int objects_processed <- 0;
        int trips_found <- 0;
        
        loop u over: arr {
            objects_processed <- objects_processed + 1;
            
            try {
                map<string, unknown> stopObj <- map<string, unknown>(u);
                
                if "departureStopsInfo" in stopObj.keys {
                    map<string, unknown> dep <- map<string, unknown>(stopObj["departureStopsInfo"]);
                    
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
}

experiment robust_parser_test type: gui {
    output {
        display "Parser Robuste" background: #white type: 2d {
            overlay position: {10, 10} size: {450 #px, 140 #px} background: #white transparency: 0.9 border: #black {
                draw "=== PARSER ROBUSTE ===" at: {10#px, 20#px} color: #black font: font("Arial", 12, #bold);
                draw "✓ from_json uniquement" at: {10#px, 40#px} color: #green;
                draw "✓ Gestion array/objet" at: {10#px, 60#px} color: #green;
                draw "✓ Cast propre + alignement" at: {10#px, 80#px} color: #green;
                draw "✓ Paires (stop,time)" at: {10#px, 100#px} color: #green;
                draw "Voir console pour statistiques" at: {10#px, 120#px} color: #blue;
            }
        }
    }
}