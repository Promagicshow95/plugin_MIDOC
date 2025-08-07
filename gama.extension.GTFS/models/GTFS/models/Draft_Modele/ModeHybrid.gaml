/**
* Name: IndexIncrementalMoving
* Based on the internal empty template. 
* Author: tiend
* Tags: 
*/

model IndexIncrementalMoving

global {
	gtfs_file gtfs_f <- gtfs_file("../../includes/tisseo_gtfs_v2");
	date min_date_gtfs <- starting_date_gtfs(gtfs_f);
    date max_date_gtfs <- ending_date_gtfs(gtfs_f);
	shape_file boundary_shp <- shape_file("../../includes/shapeFileToulouse.shp");
	geometry shape <- envelope(boundary_shp);
	graph local_network;
	int shape_id;
	map<int, graph> shape_graphs;
	string formatted_time;
	int time_24h -> int(current_date - date([1970,1,1,0,0,0])) mod 86400;
	int current_seconds_mod <- 0;

	// --- CONFIGURATION PRINCIPALE ---
	date starting_date <- date("2025-05-17T08:00:00"); // Format avec heure spécifique
	float step <- 5 #s;
	
	// --- PARAMÈTRES DE MODE HYBRIDE ---
	string simulation_mode <- "SINGLE_PERIOD"; // "SINGLE_PERIOD" ou "MULTI_DAY"
	int max_simulation_days <- 1; // 1 pour SINGLE_PERIOD, 7+ pour MULTI_DAY
	
	// --- VARIABLES POUR CONTRÔLER LE LANCEMENT ---
	int simulation_start_time; // Calculé automatiquement à partir de starting_date
	
	int total_trips_to_launch <- 0;
	int launched_trips_count <- 0;
	int current_day <- 1; // Commencer au jour 1
	list<string> launched_trip_ids <- []; // Liste globale des trips déjà lancés

	init {
		// --- SYNCHRONISATION AUTOMATIQUE DES TEMPS ---
		simulation_start_time <- (starting_date.hour * 3600) + (starting_date.minute * 60) + starting_date.second;
		
		write "🚀 === INITIALISATION MODÈLE HYBRIDE ===";
		write "📅 Date de démarrage : " + starting_date;
		write "⏰ Heure synchronisée : " + simulation_start_time + "s (" + (simulation_start_time / 3600) + "h" + ((simulation_start_time mod 3600) / 60) + "m)";
		write "🎮 Mode sélectionné : " + simulation_mode;
		
		if (simulation_mode = "MULTI_DAY") {
			write "📊 Nombre de jours à simuler : " + max_simulation_days;
		}
		
		write "Le premier jour du GTFS = " + min_date_gtfs;
        write "Le dernier jour du GTFS = " + max_date_gtfs;
		current_day <- 1; // Initialiser au jour 1
		
		create bus_stop from: gtfs_f {}
		create transport_shape from: gtfs_f {}

		// Prégénérer tous les graphes par shapeId
		loop s over: transport_shape {
			shape_graphs[s.shapeId] <- as_edge_graph(s);
		}
	}
	
	int get_time_now {
		int dof <- floor((int(current_date - date([1970,1,1,0,0,0]))) / 86400);
		return time_24h;
	}
	
	reflex update_time_every_cycle {
    	current_seconds_mod <- get_time_now();
	}
	
	reflex show_metro_trip_count when: cycle = 1 {
   		total_trips_to_launch <- sum((bus_stop where (each.routeType = 1)) collect each.tripNumber);
   		write "🟣 Total des trips métro (routeType = 1) = " + total_trips_to_launch;
	}
	
	// --- REFLEX PRINCIPAL : Gestion de fin de période/jour selon le mode ---
	reflex check_end_condition when: launched_trips_count >= total_trips_to_launch {
		
		if (simulation_mode = "SINGLE_PERIOD") {
			// --- OPTION A : Arrêt après une seule période ---
			write "🏁 === SIMULATION PÉRIODE UNIQUE TERMINÉE ===";
			write "📊 Résumé final :";
			write "   🕐 Période simulée : " + (simulation_start_time / 3600) + "h" + ((simulation_start_time mod 3600) / 60) + "m";
			write "   🚌 Total trips lancés : " + launched_trips_count;
			write "   📈 Bus encore actifs : " + length(bus);
			
			do pause;
			
		} else if (simulation_mode = "MULTI_DAY") {
			// --- OPTION MULTI-DAY : Cycle multi-jours ---
			
			if (current_day >= max_simulation_days) {
				// Simulation terminée
				write "🏁 === SIMULATION MULTI-JOURS TERMINÉE ===";
				write "📊 Résumé sur " + max_simulation_days + " jours :";
				write "   🚌 Total trips lancés : " + launched_trips_count;
				write "   📈 Bus encore actifs : " + length(bus);
				
				do pause;
				
			} else {
				// Passage au jour suivant
				current_day <- current_day + 1;
				launched_trips_count <- 0;
				launched_trip_ids <- [];
				
				// Réinitialiser les index des bus_stop pour recommencer à l'heure choisie
				ask bus_stop where (each.routeType = 1) {
					current_trip_index <- find_next_trip_index_after_time(simulation_start_time);
				}
				
				write "🌅 === PASSAGE AU JOUR " + current_day + " ===";
				write "⏰ Reprise à " + (simulation_start_time / 3600) + "h" + ((simulation_start_time mod 3600) / 60) + "m";
			}
		}
	}
}

species bus_stop skills: [TransportStopSkill] {
	rgb customColor <- rgb(0,0,255);
    map<string, bool> trips_launched;
    list<string> ordered_trip_ids;
    int current_trip_index <- 0;
    bool initialized <- false;

	// --- FONCTION POUR TROUVER LE PROCHAIN TRIP APRÈS L'HEURE CIBLE ---
	int find_next_trip_index_after_time(int target_time) {
        if (ordered_trip_ids = nil or length(ordered_trip_ids) = 0) { 
            return 0; 
        }
        
        if (departureStopsInfo = nil) {
            return 0;
        }
        
        loop i from: 0 to: length(ordered_trip_ids) - 1 {
            string trip_id <- ordered_trip_ids[i];
            
            if (departureStopsInfo contains_key trip_id) {
                list<pair<bus_stop, string>> trip_info <- departureStopsInfo[trip_id];
                
                if (trip_info != nil and length(trip_info) > 0) {
                    int departure_time <- int(trip_info[0].value);
                    
                    if (departure_time >= target_time) {
                        return i;
                    }
                }
            }
        }
        return length(ordered_trip_ids);
    }
        
    init {}
		
	// --- INITIALISATION AVEC CHOIX DE MODE ---
    reflex init_test when: cycle = 1 {
        ordered_trip_ids <- keys(departureStopsInfo);
        if (ordered_trip_ids != nil) {
        	if (simulation_mode = "SINGLE_PERIOD") {
        		// Mode SINGLE_PERIOD : Commencer à l'heure spécifiée
        		current_trip_index <- find_next_trip_index_after_time(simulation_start_time);
        		write "🕐 Stop " + self + " (SINGLE_PERIOD) : Premier trip à l'index " + current_trip_index + 
                      " (cherche à partir de " + (simulation_start_time / 3600) + "h" + ((simulation_start_time mod 3600) / 60) + "m)";
        	} else {
        		// Mode MULTI_DAY : Commencer depuis le début de la journée (00:00)
        		current_trip_index <- 0;
        		write "🌅 Stop " + self + " (MULTI_DAY) : Démarrage depuis 00:00, index " + current_trip_index;
        	}
        }
    }

	// --- LOGIQUE DE LANCEMENT DES BUS AVEC CONTRÔLE GLOBAL ---
	reflex launch_all_vehicles when: (departureStopsInfo != nil and current_trip_index < length(ordered_trip_ids) and routeType = 1) {
		string trip_id <- ordered_trip_ids[current_trip_index];
		list<pair<bus_stop, string>> trip_info <- departureStopsInfo[trip_id];
		string departure_time <- trip_info[0].value;

		// Empêcher de lancer un trip déjà lancé globalement
		if (current_seconds_mod >= int(departure_time) and not (trip_id in launched_trip_ids)) {
			int shape_found <- tripShapeMap[trip_id] as int;
			if (shape_found != 0) {
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
				current_trip_index <- (current_trip_index + 1) mod length(ordered_trip_ids);
				
				write "🚌 Lancé bus trip " + trip_id + " à " + (current_seconds_mod / 3600) + "h" + 
				      ((current_seconds_mod mod 3600) / 60) + "m (prévu: " + 
				      (int(departure_time) / 3600) + "h" + ((int(departure_time) mod 3600) / 60) + "m)";
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
	int creation_time; // Temps où le bus est créé (en secondes)
	int end_time;       // Temps où le bus meurt (en secondes)
	int real_duration;  // Durée réelle du trip en secondes (end_time - creation_time)
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
	list<int> arrival_time_diffs_pos <- []; // Liste des écarts de temps
	list<int> arrival_time_diffs_neg <- [];
	bool waiting_at_stop <- true;
	

	init {
		speed <- 10 #km/#h;
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
			// L'heure est atteinte, on peut partir
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
	        
	        // Calcul de l'écart de temps à l'arrivée
	        int expected_arrival_time <- departureStopsInfo[current_stop_index].value as int;
	        int actual_time <- current_local_time;
	        int time_diff_at_stop <-  expected_arrival_time - actual_time ;
	        
	        // Ajouter dans la bonne liste
	         if (time_diff_at_stop < 0) {
    			arrival_time_diffs_neg << time_diff_at_stop; // ❌ Retard (négatif)
			} else {
    			arrival_time_diffs_pos << time_diff_at_stop; // ✅ Avance (positif)
			}
	
	        // Préparer l'étape suivante
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
	// --- PARAMÈTRES CONFIGURABLES ---
	parameter "🎮 Mode de simulation" var: simulation_mode category: "Configuration" 
	          among: ["SINGLE_PERIOD", "MULTI_DAY"];
	parameter "📅 Date et heure de démarrage" var: starting_date category: "Configuration";
	parameter "📊 Nombre de jours (si MULTI_DAY)" var: max_simulation_days category: "Configuration";

	output {
		display "Bus Simulation" {
			species bus_stop aspect: base refresh: true;
			species bus aspect: base;
			species transport_shape aspect: default;
		}
		
		 display monitor {
            chart "Mean arrival time diff" type: series
            {
                data "Mean Early" value: mean(bus collect mean(each.arrival_time_diffs_pos)) color: #green marker_shape: marker_empty style: spline;
                data "Mean Late" value: mean(bus collect mean(each.arrival_time_diffs_neg)) color: #red marker_shape: marker_empty style: spline;
            }

			chart "Number of bus" type: series 
			{
				data "Total bus" value: length(bus);
				data "Trips launched" value: launched_trips_count;
			}
        }
	}
}