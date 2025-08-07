/**
* Name: IndexIncrementalMoving - Version corrigée
* Correction du problème de lancement massif de bus
* Author: tiend (modifié)
*/

model IndexIncrementalMoving

global {
	gtfs_file gtfs_f <- gtfs_file("../../includes/nantes_gtfs");
	date min_date_gtfs <- starting_date_gtfs(gtfs_f);
    date max_date_gtfs <- ending_date_gtfs(gtfs_f);
	shape_file boundary_shp <- shape_file("../../includes/shapeFileNantes.shp");
	geometry shape <- envelope(boundary_shp);
	graph local_network;
	int shape_id;
	map<int, graph> shape_graphs;
	string formatted_time;
	int time_24h -> int(current_date - date([1970,1,1,0,0,0])) mod 86400;
	int current_seconds_mod <- 0;

	date starting_date <- date("2025-05-17T16:00:00");
	float step <- 10 #s;
	
	// --- NOUVELLES VARIABLES POUR CONTRÔLER LE LANCEMENT ---
	int simulation_start_time <- 16 * 3600; // 16:00 en secondes
	int launch_window_seconds <- 300; // Fenêtre de 5 minutes pour lancer les bus
	int max_buses_per_cycle <- 10; // Limite de bus créés par cycle
	
	// --- NOUVELLES VARIABLES POUR GRAPHIQUE DE LANCEMENT ---
	int buses_launched_this_cycle <- 0;
	int total_buses_launched <- 0;
	int buses_launched_per_minute <- 0;
	int last_minute <- -1;
	
	int total_trips_to_launch <- 0;
	int launched_trips_count <- 0;
	int current_day <- 0;
	list<string> launched_trip_ids <- [];

	init {
		write "Le premier jour du GTFS = " + min_date_gtfs;
        write "Le dernier jour du GTFS = " + max_date_gtfs;
        write "⏰ Heure de démarrage simulation : " + simulation_start_time + " secondes (" + (simulation_start_time / 3600) + "h)";
        
		current_day <- floor((int(current_date - date([1970,1,1,0,0,0]))) / 86400);
		create bus_stop from: gtfs_f {}
		create transport_shape from: gtfs_f {}

		// Prégénérer tous les graphes par shapeId
		loop s over: transport_shape {
			shape_graphs[s.shapeId] <- as_edge_graph(s);
		}
	}
	
	int get_time_now {
		int dof <- floor((int(current_date - date([1970,1,1,0,0,0]))) / 86400);
		if dof > current_day {
			return time_24h + 86400;
		}
		return time_24h;
	}
	
	reflex update_time_every_cycle {
    	current_seconds_mod <- get_time_now();
    	
    	// --- COMPTEUR DE BUS LANCÉS PAR MINUTE ---
    	int current_minute <- current_seconds_mod / 60;
    	if (current_minute != last_minute) {
    		buses_launched_per_minute <- 0;
    		last_minute <- current_minute;
    	}
    	
    	// Réinitialiser le compteur de bus lancés ce cycle
    	buses_launched_this_cycle <- 0;
	}
	
	reflex show_metro_trip_count when: cycle = 1 {
   		total_trips_to_launch <- sum((bus_stop where (each.routeType = 3)) collect each.tripNumber);
   		write "🟣 Total des trips métro (routeType = 3) = " + total_trips_to_launch;
	}
	
	reflex check_new_day when: launched_trips_count >= total_trips_to_launch {
		int sim_day_index <- floor((int(current_date - date([1970,1,1,0,0,0]))) / 86400);
		if sim_day_index > current_day {
			current_day <- sim_day_index;
			launched_trips_count <- 0;
			launched_trip_ids <- []; 
			ask bus_stop where (each.routeType = 3) {
				current_trip_index <- 0;
			}
			write "🌙 Tous les trips ont été lancés. → Passage au jour " + current_day;
		}
	}
}

species bus_stop skills: [TransportStopSkill] {
	rgb customColor <- rgb(0,0,255);
    map<string, bool> trips_launched;
    list<string> ordered_trip_ids <- []; // --- INITIALISATION EXPLICITE ---
    int current_trip_index <- 0;
    bool initialized <- false;
    
    init {
        // --- INITIALISATION SÉCURISÉE DÈS LA CRÉATION ---
        ordered_trip_ids <- [];
        current_trip_index <- 0;
    }
		
    reflex init_test when: cycle = 1 {
        // --- CORRECTION : Vérification de sécurité ---
        if (departureStopsInfo != nil and length(keys(departureStopsInfo)) > 0) {
            ordered_trip_ids <- keys(departureStopsInfo);
            write "🚏 Initialisation du stop " + self + " avec " + length(ordered_trip_ids) + " trips";
            
            current_trip_index <- find_next_trip_index_after_time(simulation_start_time);
            write "🕐 Stop " + self + " : Premier trip à lancer à l'index " + current_trip_index;
        } else {
            write "⚠️ Stop " + self + " : Aucune information de départ disponible";
            ordered_trip_ids <- [];
            current_trip_index <- 0;
        }
    }
    
    // --- NOUVELLE ACTION : Trouver le prochain trip après une heure donnée avec sécurité ---
    int find_next_trip_index_after_time(int target_time) {
        if (ordered_trip_ids = nil or length(ordered_trip_ids) = 0) { 
            return 0; 
        }
        
        // --- PROTECTION : Vérifier que departureStopsInfo existe ---
        if (departureStopsInfo = nil) {
            return 0;
        }
        
        loop i from: 0 to: length(ordered_trip_ids) - 1 {
            string trip_id <- ordered_trip_ids[i];
            
            // --- VÉRIFICATION : Le trip existe-t-il dans departureStopsInfo ? ---
            if (departureStopsInfo contains_key trip_id) {
                list<pair<bus_stop, string>> trip_info <- departureStopsInfo[trip_id];
                
                // --- VÉRIFICATION : trip_info est-il valide ? ---
                if (trip_info != nil and length(trip_info) > 0) {
                    int departure_time <- int(trip_info[0].value);
                    
                    if (departure_time >= target_time) {
                        return i;
                    }
                }
            }
        }
        return length(ordered_trip_ids); // Tous les trips sont passés
    }

	// --- REFLEX MODIFIÉ : Contrôle du lancement avec vérifications de sécurité renforcées ---
	reflex launch_vehicles_controlled when: (departureStopsInfo != nil and 
	                                        ordered_trip_ids != nil and
	                                        length(ordered_trip_ids) > 0 and
	                                        current_trip_index < length(ordered_trip_ids) and 
	                                        routeType = 3) {
		
		// Limiter le nombre de bus créés par cycle pour éviter les pics
		int buses_created_this_cycle <- 0;
		
		// --- CORRECTION MAJEURE : Vérification à chaque itération ---
		loop while: (ordered_trip_ids != nil and 
		           current_trip_index < length(ordered_trip_ids) and 
		           buses_created_this_cycle < max_buses_per_cycle) {
		           
			string trip_id <- ordered_trip_ids[current_trip_index];
			
			// --- VÉRIFICATION : S'assurer que le trip existe dans departureStopsInfo ---
			if (departureStopsInfo contains_key trip_id) {
				list<pair<bus_stop, string>> trip_info <- departureStopsInfo[trip_id];
				
				// --- VÉRIFICATION : S'assurer que trip_info n'est pas vide ---
				if (trip_info != nil and length(trip_info) > 0) {
					int departure_time <- int(trip_info[0].value);

					// --- CORRECTION : Fenêtre de lancement plus stricte ---
					bool should_launch <- (current_seconds_mod >= departure_time) and 
					                     (current_seconds_mod <= departure_time + launch_window_seconds) and
					                     not (trip_id in launched_trip_ids);

					if (should_launch) {
						// --- VÉRIFICATION : S'assurer que tripShapeMap contient le trip ---
						if (tripShapeMap contains_key trip_id) {
							int shape_found <- tripShapeMap[trip_id] as int;
							if (shape_found != 0 and length(trip_info) > 1) {
								shape_id <- shape_found;
								create bus with: [
									departureStopsInfo:: trip_info,
									current_stop_index :: 0,
									location :: trip_info[0].key.location,
									target_location :: trip_info[1].key.location,
									trip_id :: int(trip_id),
									route_type :: self.routeType,
									shapeID :: shape_id,
									loop_starting_day:: current_day,
									local_network :: shape_graphs[shape_id]
								];

								launched_trips_count <- launched_trips_count + 1;
								launched_trip_ids <- launched_trip_ids + trip_id;
								buses_created_this_cycle <- buses_created_this_cycle + 1;
								
								// --- COMPTEURS POUR GRAPHIQUES ---
								buses_launched_this_cycle <- buses_launched_this_cycle + 1;
								total_buses_launched <- total_buses_launched + 1;
								buses_launched_per_minute <- buses_launched_per_minute + 1;
								
								write "🚌 Lancé bus trip " + trip_id + " à " + (current_seconds_mod / 3600) + "h" + 
								      ((current_seconds_mod mod 3600) / 60) + "m (prévu: " + 
								      (departure_time / 3600) + "h" + ((departure_time mod 3600) / 60) + "m)";
							} else {
								write "⚠️ Trip " + trip_id + " : Shape introuvable ou trip_info insuffisant";
							}
						} else {
							write "⚠️ Trip " + trip_id + " : Pas de shape associée dans tripShapeMap";
						}
						current_trip_index <- current_trip_index + 1;
					} else if (current_seconds_mod > departure_time + launch_window_seconds) {
						// Trip manqué, passer au suivant
						write "⏰ Trip " + trip_id + " manqué (trop tard), passage au suivant";
						current_trip_index <- current_trip_index + 1;
					} else {
						// Pas encore l'heure, sortir de la boucle
						break;
					}
				} else {
					write "⚠️ Trip " + trip_id + " : trip_info vide ou null";
					current_trip_index <- current_trip_index + 1;
				}
			} else {
				write "⚠️ Trip " + trip_id + " : Introuvable dans departureStopsInfo";
				current_trip_index <- current_trip_index + 1;
			}
		}
	}

	aspect base {
		draw circle(20) color: customColor;
	}
}

species transport_shape skills: [TransportShapeSkill] {
	aspect default { draw shape color: #black; }
}

species bus skills: [moving] {
	graph local_network;

	aspect base {
        if (route_type = 1) {
            draw rectangle(150, 200) color: #red rotate: heading;
        } else if (route_type = 3) {
            draw rectangle(100, 150) color: #green rotate: heading;
        } else {
            draw rectangle(110, 170) color: #blue rotate: heading;
        }
    }
    
	int creation_time;
	int end_time;
	int real_duration;
	int current_stop_index <- 0;
	point target_location;
	list<pair<bus_stop,string>> departureStopsInfo;
	int trip_id;
	int shapeID;
	int route_type;
	int duration;
	int loop_starting_day;
	int current_local_time;
	list<float> list_stop_distance;
	list<int> arrival_time_diffs_pos <- [];
	list<int> arrival_time_diffs_neg <- [];
	bool waiting_at_stop <- true;

	init {
		speed <- 50 #km/#h;
		creation_time <- get_local_time_now();
	}

	int get_local_time_now {
		int dof <- floor((int(current_date - date([1970,1,1,0,0,0]))) / 86400);
		if dof > loop_starting_day {
			return time_24h + 86400;
		}
		return time_24h;
	}

	reflex update_time_every_cycle {
		current_local_time <- get_local_time_now();
	}
	
	reflex wait_at_stop when: waiting_at_stop {
		int stop_time <- departureStopsInfo[current_stop_index].value as int;
		if (current_local_time >= stop_time) {
			waiting_at_stop <- false;
		}
	}

	reflex move when: not waiting_at_stop and self.location distance_to target_location > 5#m {
		do goto target: target_location on: local_network speed: speed;
		if location distance_to target_location < 5#m{ 
			location <- target_location;
		}
	}

	reflex check_arrival when: self.location distance_to target_location < 5#m and not waiting_at_stop {
	    if (current_stop_index < length(departureStopsInfo) - 1) {
	        int expected_arrival_time <- departureStopsInfo[current_stop_index].value as int;
	        int actual_time <- current_local_time;
	        int time_diff_at_stop <- expected_arrival_time - actual_time;
	        
	        if (time_diff_at_stop < 0) {
    			arrival_time_diffs_neg << time_diff_at_stop;
			} else {
    			arrival_time_diffs_pos << time_diff_at_stop;
			}

	        current_stop_index <- current_stop_index + 1;
	        target_location <- departureStopsInfo[current_stop_index].key.location;
	        waiting_at_stop <- true;
	    }
	    
	    if (current_stop_index = length(departureStopsInfo) - 1) {
	    	end_time <- current_local_time;
			real_duration <- end_time - creation_time;
	        do die;
	    }
	}
}

experiment GTFSExperiment type: gui {
	parameter "Heure de démarrage (heures)" var: simulation_start_time category: "Simulation" min: 0 max: 86400;
	parameter "Fenêtre de lancement (secondes)" var: launch_window_seconds category: "Simulation" min: 60 max: 1800;
	parameter "Max bus par cycle" var: max_buses_per_cycle category: "Simulation" min: 1 max: 50;

	output {
		display "Bus Simulation" {
			species bus_stop aspect: base refresh: true;
			species bus aspect: base;
			species transport_shape aspect: default;
		}
		
		display "Statistiques de lancement de bus" {
			chart "Nombre de bus lancés" type: series {
				data "Bus lancés ce cycle" value: buses_launched_this_cycle color: #red;
				data "Bus lancés par minute" value: buses_launched_per_minute color: #orange;
			}
			
			chart "Cumul des lancements" type: series {
				data "Total bus lancés" value: total_buses_launched color: #blue;
				data "Bus actuellement actifs" value: length(bus) color: #green;
			}
		}
		
		// Moniteurs pour debugger
		monitor "Heure simulation" value: string(current_seconds_mod / 3600) + "h" + string((current_seconds_mod mod 3600) / 60) + "m";
		monitor "Bus actuellement actifs" value: length(bus);
		monitor "🚌 Bus lancés ce cycle" value: buses_launched_this_cycle;
		monitor "📊 Total bus lancés" value: total_buses_launched;
		monitor "⏱️ Bus lancés cette minute" value: buses_launched_per_minute;
	}
}