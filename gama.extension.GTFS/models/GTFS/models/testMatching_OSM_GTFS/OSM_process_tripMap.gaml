/**
* Name: TestJSON - Extension pour tous les arrêts
* Based on the internal empty template. 
* Author: benoitgaudou
* Tags: 
*/

model TestJSON

/* Insert your model definition here */

global {
    string results_folder <- "../../results/";
    string stops_folder <- "../../results/stopReseau/";
	
	// Structure unifiée pour tous les trips de tous les arrêts
	map<string, list<pair<string, int>>> trip_to_sequence;
	
	// Statistiques pour suivi du traitement
	int total_stops_processed <- 0;
	int total_trips_processed <- 0;
	map<string, int> collision_check;
	
	init {
	}
	
	reflex step1 when: cycle = 0 {
		do pre_read_and_parse_json_all_stops;
	}
	
	// TRAITEMENT ÉTENDU POUR TOUS LES ARRÊTS
    action pre_read_and_parse_json_all_stops {
        write "ÉTAPE 1: Construction trip_to_sequence pour TOUS les arrêts";
        
        string json_filename <- stops_folder + "departure_stops_info_stopid.json";
        trip_to_sequence <- map<string, list<pair<string, int>>>([]);
        collision_check <- map<string, int>([]);
        
        write "→ Lecture du fichier: " + json_filename;
        
        file json_f <- text_file(json_filename);
        string content <- string(json_f);
        
        write "→ Fichier lu, taille: " + length(content) + " caractères";
        
        map<string, unknown> json_data <- from_json(content);
        write "→ JSON parsé avec succès";
        
        if !(json_data contains_key "departure_stops_info") {
            write "ERREUR: Clé 'departure_stops_info' manquante";
            return;
        }
        
        list<map<string, unknown>> stops_list <- list<map<string, unknown>>(json_data["departure_stops_info"]);
        write "→ JSON lu: " + length(stops_list) + " arrêts à traiter";
        write "";
        
        // TRAITER TOUS LES ARRÊTS
        loop stop_index from: 0 to: length(stops_list)-1 {
            map<string, unknown> stop_data <- stops_list[stop_index];
            string current_stop_id <- string(stop_data["stopId"]);
            
            // Vérifier que departureStopsInfo existe
            if !(stop_data contains_key "departureStopsInfo") {
                write "⚠️  Arrêt " + current_stop_id + " sans departureStopsInfo, ignoré";
                continue;
            }
            
            map<string,unknown> subMap <- stop_data["departureStopsInfo"];
            total_stops_processed <- total_stops_processed + 1;
            
            // Ignorer les arrêts sans trips
            if length(subMap.keys) = 0 {
                if stop_index < 5 {
                    write "→ Arrêt " + (stop_index+1) + "/" + length(stops_list) + ": " + current_stop_id + " (0 trips, ignoré)";
                }
                continue;
            }
            
            // Messages de progression (échantillonnage pour éviter la verbosité)
            if stop_index < 5 or stop_index mod 50 = 0 or stop_index = length(stops_list)-1 {
                write "→ Arrêt " + (stop_index+1) + "/" + length(stops_list) + ": " + current_stop_id + " (" + length(subMap.keys) + " trips)";
            }
            
            // TRAITER TOUS LES TRIPS DE CET ARRÊT
            loop trip_id over: subMap.keys {
                // Vérifier les collisions de trip_id
                if collision_check contains_key trip_id {
                    collision_check[trip_id] <- collision_check[trip_id] + 1;
                    if collision_check[trip_id] = 2 {
                        write "⚠️  COLLISION détectée: trip_id '" + trip_id + "' trouvé dans plusieurs arrêts";
                    }
                } else {
                    collision_check[trip_id] <- 1;
                }
                
                // Éviter de traiter plusieurs fois le même trip
                if !(trip_to_sequence contains_key trip_id) {
                    // DEBUG INTENSIF : Analyser le problème de casting
                    unknown raw_data <- subMap[trip_id];
                    write "    🔍 DEBUG trip " + trip_id + ":";
                    write "        Type brut: " + type_of(raw_data);
                    write "        Contenu brut: " + string(raw_data);
                    
                    // Essayer le casting habituel
                    list<list<string>> sequence <- list<list<string>>(raw_data);
                    write "        Après casting: taille=" + length(sequence);
                    
                    if length(sequence) = 0 {
                        write "        ❌ PROBLÈME: Séquence vide après casting!";
                        continue;
                    } else {
                        write "        ✓ Séquence OK: " + length(sequence) + " éléments";
                        write "        Premier élément: " + sequence[0];
                    }
                    
                    list<pair<string, int>> sequence_parsed <- [];
                    
                    loop stop_time_pair over: sequence {
                        write "          Traitement paire: " + stop_time_pair + " (taille: " + length(stop_time_pair) + ")";
                        if length(stop_time_pair) >= 2 {
                            string stop_id <- stop_time_pair[0];
                            int time_value <- int(stop_time_pair[1]);
                            add pair(stop_id, time_value) to: sequence_parsed;
                            write "            ✓ Paire ajoutée: " + stop_id + " → " + time_value;
                        } else {
                            write "            ❌ Paire trop courte: " + stop_time_pair;
                        }
                    }
                    
                    // Stocker seulement si la séquence parsée n'est pas vide
                    if length(sequence_parsed) > 0 {
                        trip_to_sequence[trip_id] <- sequence_parsed;
                        total_trips_processed <- total_trips_processed + 1;
                        write "        ✅ Trip " + trip_id + " ajouté avec " + length(sequence_parsed) + " arrêts";
                    } else {
                        write "        ❌ Trip " + trip_id + " n'a produit aucune paire valide, ignoré";
                    }
                }
            }
        }
        
        write "";
        write "=== TRAITEMENT TERMINÉ ===";
        write "→ Arrêts traités: " + total_stops_processed;
        write "→ Trips uniques dans trip_to_sequence: " + length(trip_to_sequence.keys);
        write "→ Trips traités au total: " + total_trips_processed;
        
        // Vérifications et analyses
        do analyze_collision_results;
        do verify_global_trip_structure;
        do show_network_statistics;
    }
    
    // ANALYSE DES COLLISIONS DE TRIP_ID
    action analyze_collision_results {
        write "";
        write "=== ANALYSE DES COLLISIONS ===";
        
        int unique_trips <- 0;
        int collisions_found <- 0;
        
        loop trip_id over: collision_check.keys {
            int count <- collision_check[trip_id];
            if count = 1 {
                unique_trips <- unique_trips + 1;
            } else {
                collisions_found <- collisions_found + 1;
            }
        }
        
        if collisions_found = 0 {
            write "✓ Aucune collision: tous les trip_id sont uniques";
            write "✓ Structure trip_to_sequence OPTIMALE pour simulation";
        } else {
            write "⚠️  " + collisions_found + " collisions détectées";
            write "→ Trips uniques: " + unique_trips;
            write "→ Trips en collision: " + collisions_found;
            write "⚠️  Une structure hiérarchique pourrait être nécessaire";
        }
        write "===============================";
    }
    
    // VÉRIFICATION DE LA STRUCTURE GLOBALE
    action verify_global_trip_structure {
        write "";
        write "=== VÉRIFICATION STRUCTURE GLOBALE ===";
        
        if length(trip_to_sequence.keys) = 0 {
            write "❌ ERREUR: trip_to_sequence est vide!";
            return;
        }
        
        write "✓ Type: " + type_of(trip_to_sequence);
        write "✓ Trips dans le réseau: " + length(trip_to_sequence.keys);
        
        // Statistiques des séquences
        int total_stops <- 0;
        int min_stops <- 999;
        int max_stops <- 0;
        int min_time <- 999999;
        int max_time <- 0;
        
        loop trip_sequence over: trip_to_sequence.values {
            int seq_length <- length(trip_sequence);
            total_stops <- total_stops + seq_length;
            
            if seq_length < min_stops { min_stops <- seq_length; }
            if seq_length > max_stops { max_stops <- seq_length; }
            
            // Vérifier que la séquence n'est pas vide avant d'accéder aux éléments
            if seq_length > 0 {
                int first_time <- trip_sequence[0].value;
                int last_time <- trip_sequence[seq_length-1].value;
                
                if first_time < min_time { min_time <- first_time; }
                if last_time > max_time { max_time <- last_time; }
            }
        }
        
        write "✓ Total arrêts dans toutes les séquences: " + total_stops;
        write "✓ Longueur des séquences: " + min_stops + " à " + max_stops + " arrêts";
        write "✓ Plage temporelle globale: " + convert_seconds_to_time(min_time) + " → " + convert_seconds_to_time(max_time);
        write "✓ Moyenne arrêts/trip: " + (total_stops / length(trip_to_sequence.keys));
        write "=====================================";
    }
    
    // STATISTIQUES DU RÉSEAU
    action show_network_statistics {
        write "";
        write "=== STATISTIQUES DU RÉSEAU ===";
        
        // Échantillon de trips de différentes sources
        list<string> sample_trips <- [];
        int samples_shown <- 0;
        
        loop trip_id over: trip_to_sequence.keys {
            if samples_shown < 5 {
                sample_trips <- sample_trips + trip_id;
                samples_shown <- samples_shown + 1;
            }
        }
        
        write "Échantillon de trips dans le réseau:";
        loop sample_trip over: sample_trips {
            list<pair<string, int>> route <- trip_to_sequence[sample_trip];
            
            // Vérifier que la route n'est pas vide
            if length(route) > 0 {
                pair<string, int> first_stop <- route[0];
                pair<string, int> last_stop <- route[length(route)-1];
                
                write "  " + sample_trip + ": " + first_stop.key + " (" + convert_seconds_to_time(first_stop.value) + ") → " + last_stop.key + " (" + convert_seconds_to_time(last_stop.value) + ") [" + length(route) + " arrêts]";
            } else {
                write "  " + sample_trip + ": route vide";
            }
        }
        
        write "";
        write "🚌 RÉSEAU PRÊT POUR SIMULATION:";
        write "   - Accès direct: trip_to_sequence[trip_id]";
        write "   - " + length(trip_to_sequence.keys) + " véhicules potentiels";
        write "   - Routes complètes avec horaires précis";
        write "===============================";
    }
    
    // FONCTION UTILITAIRE pour convertir secondes en HH:MM:SS
    string convert_seconds_to_time(int seconds) {
        int hours <- seconds div 3600;
        int minutes <- (seconds mod 3600) div 60;
        int secs <- seconds mod 60;
        
        string h_str <- hours < 10 ? "0" + hours : "" + hours;
        string m_str <- minutes < 10 ? "0" + minutes : "" + minutes;
        string s_str <- secs < 10 ? "0" + secs : "" + secs;
        
        return h_str + ":" + m_str + ":" + s_str;
    }
}

experiment TestJSONExp type: gui {
    output {
        // MONITORS TEMPORAIREMENT DÉSACTIVÉS POUR DEBUG
        // monitor "Arrêts traités" value: total_stops_processed;
        // monitor "Trips dans réseau" value: length(trip_to_sequence.keys);
        // monitor "Trips traités" value: total_trips_processed;
        // monitor "Moy. arrêts/trip" value: length(trip_to_sequence.keys) > 0 ? (sum(trip_to_sequence.values collect length(each)) / length(trip_to_sequence.keys)) : 0;
        // monitor "Total arrêts réseau" value: length(trip_to_sequence.keys) > 0 ? sum(trip_to_sequence.values collect length(each)) : 0;
    }
}