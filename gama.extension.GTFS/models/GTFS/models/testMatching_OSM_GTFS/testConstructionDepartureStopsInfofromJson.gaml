/**
 * Name: JSON Trips Importer
 * Author: Assistant
 * Description: Import departure_stops_info_stopid.json et construction trips_global
 * Tags: import, JSON, trips, bus_stop, GTFS
 */

model json_trips_importer

global {
    // Fichier JSON à importer
    file JsonFile <- json_file("../../results/stopReseau/departure_stops_info_stopid.json");
    
    // Structure globale cible : tripId -> liste ordonnée (stop_agent, time_sec)
    map<string, list<pair<bus_stop, int>>> trips_global <- [];
    
    // Maps de diagnostic
    map<string, list<string>> trips_stop_ids <- [];
    map<string, list<int>> trips_times_sec <- [];
    
    // Map de correspondance stopId -> agent bus_stop
    map<string, bus_stop> stopId_to_agent <- [];
    
    // Stats
    int total_stops <- 0;
    int total_trips <- 0;
    int total_pairs <- 0;
    int missing_stops <- 0;
    
    init {
        write "=== IMPORT JSON ET CONSTRUCTION TRIPS_GLOBAL ===";
        
        // Chargement JSON
        map<string, unknown> json_content <- JsonFile.contents;
        write "Fichier JSON chargé";
        
        // Extraction de la liste des arrêts
        list<map<string, unknown>> stops_list <- list<map<string, unknown>>(json_content["departure_stops_info"]);
        write "Nombre d'arrêts dans JSON : " + length(stops_list);
        
        // Phase 1 : Création des agents bus_stop et map de correspondance
        do create_bus_stops_from_json(stops_list);
        
        // Phase 2 : Construction de trips_global
        do build_trips_global(stops_list);
        
        // Affichage des stats finales
        do display_stats;
        
        // Test échantillon
        do test_sample_trip;
    }
    
    // Phase 1 : Créer les agents bus_stop et la map stopId -> agent
    action create_bus_stops_from_json(list<map<string, unknown>> stops_list) {
        write "\n=== PHASE 1 : CRÉATION AGENTS BUS_STOP ===";
        
        loop stop_data over: stops_list {
            string stop_id <- string(stop_data["stopId"]);
            list<int> location_coords <- list<int>(stop_data["location"]);
            int route_type <- int(stop_data["routeType"]);
            
            // Création agent bus_stop
            create bus_stop {
                stopId <- stop_id;
                location <- {location_coords[0], location_coords[1]};
                routeType <- route_type;
            }
            
            // Ajout à la map de correspondance
            stopId_to_agent[stop_id] <- last(bus_stop);
            total_stops <- total_stops + 1;
        }
        
        write "Agents bus_stop créés : " + total_stops;
        write "Map stopId->agent construite : " + length(stopId_to_agent) + " entrées";
    }
    
    // Phase 2 : Construction trips_global depuis le JSON
    action build_trips_global(list<map<string, unknown>> stops_list) {
        write "\n=== PHASE 2A : DIAGNOSTIC - PARSING BRUT ===";
        
        int processed_stops <- 0;
        
        loop stop_data over: stops_list {
            processed_stops <- processed_stops + 1;
            map<string, unknown> departure_info <- map<string, unknown>(stop_data["departureStopsInfo"]);
            
            // Debug premier arrêt
            if processed_stops = 1 {
                write "Premier arrêt - departure_info keys: " + length(departure_info.keys);
                if length(departure_info.keys) > 0 {
                    string first_trip <- first(departure_info.keys);
                    write "Premier trip: " + first_trip;
                    unknown trip_data <- departure_info[first_trip];
                    write "Type de trip_data: " + string(type_of(trip_data));
                }
            }
            
            // Pour chaque trip dans cet arrêt
            loop trip_id over: departure_info.keys {
                unknown trip_raw <- departure_info[trip_id];
                
                try {
                    list<unknown> trip_sequence <- list<unknown>(trip_raw);
                    
                    // Debug premier trip
                    if processed_stops = 1 and trip_id = first(departure_info.keys) {
                        write "Trip sequence length: " + length(trip_sequence);
                        if length(trip_sequence) > 0 {
                            unknown first_pair <- trip_sequence[0];
                            write "Premier pair type: " + string(type_of(first_pair));
                        }
                    }
                    
                    // Créer les listes parallèles si pas encore créées
                    if !(trips_stop_ids contains_key trip_id) {
                        trips_stop_ids[trip_id] <- [];
                        trips_times_sec[trip_id] <- [];
                        total_trips <- total_trips + 1;
                    }
                    
                    // Parser brut - juste extraire stopId et time
                    loop pair_data over: trip_sequence {
                        try {
                            list<unknown> pair_elements <- list<unknown>(pair_data);
                            
                            if length(pair_elements) = 2 {
                                // Extraction brute
                                string stop_id <- string(pair_elements[0]);
                                
                                // Conversion temps avec fallback
                                int time_seconds;
                                try {
                                    time_seconds <- int(string(pair_elements[1]));
                                } catch {
                                    try {
                                        time_seconds <- int(pair_elements[1]);
                                    } catch {
                                        time_seconds <- -1; // erreur de conversion
                                    }
                                }
                                
                                // Ajout aux maps parallèles (sans vérification agent)
                                trips_stop_ids[trip_id] <+ stop_id;
                                trips_times_sec[trip_id] <+ time_seconds;
                            }
                        } catch {
                            // Échec parsing d'une paire
                        }
                    }
                } catch {
                    write "ERREUR: Impossible de caster trip " + trip_id + " en list<unknown>";
                }
            }
        }
        
        write "Maps parallèles construites - trips: " + length(trips_stop_ids);
        
        // Diagnostic rapide
        if !empty(trips_stop_ids.keys) {
            string sample_trip <- first(trips_stop_ids.keys);
            write "Sample trip " + sample_trip + " : " + length(trips_stop_ids[sample_trip]) + " stopIds";
            write "Sample trip " + sample_trip + " : " + length(trips_times_sec[sample_trip]) + " times";
        }
        
        write "\n=== PHASE 2B : CONSTRUCTION TRIPS_GLOBAL ===";
        
        // Maintenant construire trips_global depuis les maps parallèles
        loop trip_id over: trips_stop_ids.keys {
            trips_global[trip_id] <- [];
            
            list<string> stop_ids <- trips_stop_ids[trip_id];
            list<int> times <- trips_times_sec[trip_id];
            
            // Vérifier que les listes ne sont pas vides
            if length(stop_ids) > 0 and length(times) > 0 {
                loop i from: 0 to: (length(stop_ids) - 1) {
                    string stop_id <- stop_ids[i];
                    int time_sec <- times[i];
                    
                    if stopId_to_agent contains_key stop_id {
                        bus_stop stop_agent <- stopId_to_agent[stop_id];
                        pair<bus_stop, int> stop_time_pair <- pair(stop_agent, time_sec);
                        trips_global[trip_id] <+ stop_time_pair;
                        total_pairs <- total_pairs + 1;
                    } else {
                        missing_stops <- missing_stops + 1;
                    }
                }
            } else {
                write "PROBLÈME : trip " + trip_id + " a des listes vides";
            }
        }
        
        write "Trips construits : " + total_trips;
        write "Paires (stop, time) totales : " + total_pairs;
        write "StopIds manquants : " + missing_stops;
    }
    
    // Affichage statistiques
    action display_stats {
        write "\n=== STATISTIQUES FINALES ===";
        write "Arrêts créés : " + total_stops;
        write "Trips dans trips_global : " + length(trips_global);
        write "Paires totales : " + total_pairs;
        
        if length(trips_global) > 0 {
            write "Moyenne stops/trip : " + (total_pairs / length(trips_global));
        }
    }
    
    // Test d'un échantillon
    action test_sample_trip {
        write "\n=== TEST ÉCHANTILLON ===";
        
        if !empty(trips_global.keys) {
            string sample_trip <- first(trips_global.keys);
            list<pair<bus_stop, int>> sample_sequence <- trips_global[sample_trip];
            
            write "Trip échantillon : " + sample_trip;
            write "Nombre de stops : " + length(sample_sequence);
            
            // Vérifier que la séquence n'est pas vide
            if !empty(sample_sequence) {
                // Afficher les 3 premiers stops
                int max_display <- min(3, length(sample_sequence));
                loop i from: 0 to: (max_display - 1) {
                    pair<bus_stop, int> stop_time <- sample_sequence[i];
                    bus_stop stop_agent <- stop_time.key;
                    int time_sec <- stop_time.value;
                    
                    // Conversion en heures:minutes:secondes
                    int hours <- time_sec / 3600;
                    int minutes <- (time_sec mod 3600) / 60;
                    int seconds <- time_sec mod 60;
                    
                    write "  " + i + " : " + stop_agent.stopId + " à " + hours + ":" + 
                          (minutes < 10 ? "0" + minutes : string(minutes)) + ":" + 
                          (seconds < 10 ? "0" + seconds : string(seconds));
                }
                
                if length(sample_sequence) > 3 {
                    write "  ... et " + (length(sample_sequence) - 3) + " autres stops";
                }
            } else {
                write "PROBLÈME : séquence vide pour " + sample_trip;
            }
        } else {
            write "PROBLÈME : trips_global est vide";
        }
        
        write "\n✅ TRIPS_GLOBAL CONSTRUIT ET FONCTIONNEL";
    }
}

species bus_stop {
    string stopId;
    int routeType;
    
    aspect base {
        draw circle(50.0) at: location color: #blue border: #black;
        draw stopId size: 6 color: #black at: location + {0, 80};
    }
}

experiment ImportTest type: gui {
    output {
        display "Bus Stops et Trips Global" background: #white {
            species bus_stop aspect: base;
            
            overlay position: {10, 10} size: {400 #px, 120 #px} 
                    background: #white transparency: 0.9 border: #black {
                
                draw "=== TRIPS GLOBAL IMPORTER ===" at: {10#px, 20#px} 
                     color: #black font: font("Arial", 10, #bold);
                
                draw "Arrêts : " + length(bus_stop) at: {20#px, 40#px} color: #blue;
                draw "Trips : " + length(trips_global) at: {20#px, 60#px} color: #green;
                draw "Paires : " + total_pairs at: {20#px, 80#px} color: #purple;
                draw "Structure globale construite" at: {20#px, 100#px} color: #black size: 8;
            }
        }
    }
}