/**
* Name: IndexIncrementalMoving
* Based on the internal empty template. 
* Author: tiend
* Tags: 
*/


model IndexIncrementalMoving

global {
	gtfs_file gtfs_f <- gtfs_file("../../includes/hanoi_gtfs_am");
	shape_file boundary_shp <- shape_file("../../includes/envelopFileNantes/gtfs-tan/routes.shp");
	geometry shape <- envelope(boundary_shp);
	graph local_network;
	int shape_id;
	map<int, graph> shape_graphs;
	string formatted_time;
	int time_24h -> int(current_date - date([1970,1,1,0,0,0])) mod 86400;
	int current_seconds_mod <- 0;

	date starting_date <- date("2024-02-21T00:00:00");
	
	float step <- 5 #s;
	
	int total_trips_to_launch <- 0;
	int launched_trips_count <- 0;
	int current_day <- 0;
	list<string> launched_trip_ids <- []; // # MODIF : Liste globale des trips déjà lancés

	init {
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
	list<string> ordered_trip_ids;
	int current_trip_index <- 0;
	bool initialized <- false;

	init {}
	
	reflex init_test when: cycle = 1 {
		ordered_trip_ids <- keys(departureStopsInfo);
		if (ordered_trip_ids != nil) {}
	}

	// --- MODIF : Logique de lancement des bus avec contrôle global des trips déjà lancés ---
	reflex launch_all_vehicles when: (departureStopsInfo != nil and current_trip_index < length(ordered_trip_ids) and routeType = 3) {
		string trip_id <- ordered_trip_ids[current_trip_index];
		list<pair<bus_stop, string>> trip_info <- departureStopsInfo[trip_id];
		string departure_time <- trip_info[0].value;

		// --- Empêcher de lancer un trip déjà lancé globalement ! ---
		if (current_seconds_mod >= int(departure_time) and not (trip_id in launched_trip_ids)) {
			int shape_found <- tripShapeMap[trip_id] as int;
			if shape_found != 0 {
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
				launched_trip_ids <- launched_trip_ids + trip_id; // # MODIF : ajouter à la liste globale
				current_trip_index <- (current_trip_index + 1) mod length(ordered_trip_ids);
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
//		if (route_type = 1) { speed <-  1000 #m/#s; }
//		else if (route_type = 3) { speed <- 17.75 #km/#h; }
//		else if (route_type = 0) { speed <- 19.8 #km/#h; }
//		else if (route_type = 6) { speed <- 17.75 #km/#h; }
//		else { speed <- 20.0 #km/#h; }
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
			// L'heure est atteinte, on peut partir
			waiting_at_stop <- false;
		}
	}
	
//	action configure_trip_speed {
//    	int n <- length(departureStopsInfo);
//    	if n > 1 {
//        	int time_first <- departureStopsInfo[0].value as int;
//        	int time_last <- departureStopsInfo[n - 1].value as int;
//        	float dist_first <- list_stop_distance[0];
//        	float dist_last <- list_stop_distance[n - 1];
//
//        	int total_time <- max(time_last - time_first, 1); // éviter div par 0
//        	float total_dist <- dist_last - dist_first;
//
//       	 	float estimated_speed <- total_dist / total_time;
//        	speed <- max(estimated_speed, 4.5); // au moins 16.2 km/h
//
//        	if (trip_id = 1900169) {
//           	 write "Estimated speed: " + speed + 
//                  " | total_time: " + total_time + 
//                  " | total_dist: " + total_dist;
//        }
//    }
//}




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
	
	//        if (trip_id = 2096254){write "✅ Arrivé au stop " + current_stop_index + " pour trip " + trip_id + 
	//              " | écart de temps entre " + actual_time + " with current date " +  current_date + " et " + expected_arrival_time + " = " + time_diff_at_stop + " sec.";
	//              write "departureStopsInfo: " + departureStopsInfo;}
	
	        // Préparer l'étape suivante
	        current_stop_index <- current_stop_index + 1;
	        target_location <- departureStopsInfo[current_stop_index].key.location;
	        waiting_at_stop <- true;
	        
//	        do configure_trip_speed();
	 
	        
	    }
	    
	    if (current_stop_index = length(departureStopsInfo) - 1) {
	    	end_time <- current_local_time;
			real_duration <- end_time - creation_time;

//			write "🚌 Bus " + trip_id + " a fini son trajet.";
//			write "Temps réel de parcours = " + real_duration + " secondes.";
	        do die;
	    }
	}


}

experiment GTFSExperiment type: gui {
	output {
		display "Bus Simulation" {
			species bus_stop aspect: base refresh: true;
			species bus aspect: base;
			species transport_shape aspect: default;
		}
		
		 display monitor {
            chart "Mean arrival time diff" type: series
            {
//                data "Mean Early" value: mean(bus collect mean(each.arrival_time_diffs_pos)) color: # green marker_shape: marker_empty style: spline;
//                data "Mean Late" value: mean(bus collect mean(each.arrival_time_diffs_neg)) color: # red marker_shape: marker_empty style: spline;
//                 data "total_trips_to_launch" value:total_trips_to_launch color: # green marker_shape: marker_empty style: spline;
//                data "launched_trips_count" value: launched_trips_count color: # red marker_shape: marker_empty style: spline;
            }

			chart "Number of bus" type: series 
			{
				data "Total bus" value: length(bus);
			}


        }
	}
}




