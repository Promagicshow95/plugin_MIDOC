/**
* Name: IndexIncrementalMoving
* Based on the internal empty template. 
* Author: tiend
* Tags: 
*/


model IndexIncrementalMoving



global {
	gtfs_file gtfs_f <- gtfs_file("../../includes/tisseo_gtfs_v2");
	shape_file boundary_shp <- shape_file("../../includes/boundaryTLSE-WGS84PM.shp");
	shape_file cleaned_road_shp <- shape_file("../../includes/cleaned_network.shp");
	geometry shape <- envelope(boundary_shp);
	graph local_network;
	graph metro_network;
	int shape_id;
	map<int, graph> shape_graphs;
	string formatted_time;
	int current_seconds_mod;

	date starting_date <- date("2024-02-21T07:00:00");
	
	
	
	float step <- 5 #s;

	init {
		//write "\ud83d\uddd3\ufe0f Chargement des donn\u00e9es GTFS...";
		create bus_stop from: gtfs_f {
		}
		create transport_shape from: gtfs_f {}
		
		// Prégénérer tous les graphes par shapeId
		loop s over: transport_shape {
			shape_graphs[s.shapeId] <- as_edge_graph(s);
		}
	}

	// Mettre à jour current_seconds_mod basé sur simulation_time
	reflex update_formatted_time {
		int current_hour <- current_date.hour;
		int current_minute <- current_date.minute;
		int current_second <- current_date.second;
//		write "current_date: " + current_date;
//		write "current_hour: "+ current_hour;
//		write "current_minute: " + current_minute;
//		write "current_second: " + current_second;

		int current_total_seconds <- current_hour * 3600 + current_minute * 60 + current_second;
		current_seconds_mod <- current_total_seconds mod 86400;
	}
}

species bus_stop skills: [TransportStopSkill] {
	rgb customColor <- rgb(0,0,255);
	map<string, bool> trips_launched;
	list<string> ordered_trip_ids;
	int current_trip_index <- 0;
	bool initialized <- false;

	init {
	}  
	
	reflex init_test when: cycle =1{
		ordered_trip_ids <- keys(departureStopsInfo);
		if (ordered_trip_ids !=nil) {}
		
	}

	
	reflex launch_all_vehicles when: (departureStopsInfo != nil and current_trip_index < length(ordered_trip_ids)){
		string trip_id <- ordered_trip_ids[current_trip_index];
		list<pair<bus_stop, string>> trip_info <- departureStopsInfo[trip_id];
		string departure_time <- trip_info[0].value;
		list<float> list_distance_stop <- departureShapeDistances[trip_id];
		
//		write "departure_time: " + departure_time;
//		write "current_time: " + current_seconds_mod;

		if (current_seconds_mod >= int(departure_time) ){
		
			int shape_found <- tripShapeMap[trip_id] as int;
			
			if shape_found != 0{
				shape_id <- shape_found;
				
				create bus with:[
					departureStopsInfo:: trip_info,
					current_stop_index :: 0,
					location :: trip_info[0].key.location,
					target_location :: trip_info[1].key.location,
					trip_id :: int(trip_id),
					route_type :: self.routeType,
					shapeID ::shape_id,
					list_stop_distance :: list_distance_stop,
					local_network :: shape_graphs[shape_id]// Utilise le graphe préchargé
				];
				
				current_trip_index <- (current_trip_index + 1) mod length(ordered_trip_ids);
				//write "current_trip_index: " + current_trip_index;
				
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

	int current_stop_index <- 0;
	point target_location;
	list<pair<bus_stop,string>> departureStopsInfo;
	int trip_id;
	int shapeID;
	int route_type;
	int duration;
	list<float> list_stop_distance;
	list<int> arrival_time_diffs_pos <- []; // Liste des écarts de temps
	list<int> arrival_time_diffs_neg <- [];
	bool waiting_at_stop <- true;
	

	init {
		//speed <- 35 #km/#h;
	}
	
	reflex wait_at_stop when: waiting_at_stop {
		int stop_time <- departureStopsInfo[current_stop_index].value as int;

		if (current_seconds_mod >= stop_time) {
			// L'heure est atteinte, on peut partir
			waiting_at_stop <- false;
		}
	}
	
	reflex configure_speed when: not waiting_at_stop {
    if (current_stop_index < length(departureStopsInfo) - 1) {
        // Récupérer l'heure de départ du stop actuel
        int time_value_current <- departureStopsInfo[current_stop_index].value as int ;
        int  time_value_next <- departureStopsInfo[current_stop_index + 1].value as int;


        // Récupérer la distance cumulée
        float first_distance <- list_stop_distance[current_stop_index];
        float next_stop_distance <- list_stop_distance[current_stop_index + 1];
        
        int time_diff <- time_value_next - time_value_current;
        float distance_diff <- next_stop_distance - first_distance;
        
        //write "⏰ time_diff entre stops for trip " + trip_id + " is "  + current_stop_index + " ➡️ " + (current_stop_index + 1) + ": " + time_diff  + " s" ;
        //write "📏 distance_diff entre stops: " + distance_diff + " m";

        if (time_diff > 0 and distance_diff > 0) {
            speed <- (distance_diff / time_diff) #m/#s;
//            write "🚍 Nouvelle speed: " + speed + " m/s";
        } else {
          	int first_time <- departureStopsInfo[0].value as int;
			int last_index <- length(departureStopsInfo) - 1;
			int last_time <- departureStopsInfo[last_index].value as int;

			duration <- last_time - first_time;
			if duration <= 0 {
			//write "⚠️ Durée du trip non valide pour trip " + trip_id;
			speed <- 1000 #m/#s; 
			//speed <- distance_diff;
		} 
		else {
			// Récupérer la géométrie du trajet via shapeId
			geometry geom <- (transport_shape first_with (each.shapeId = shapeID)).shape;
		
			float dist <- perimeter(geom); // en mètres
			speed <- (dist / duration) #m/#s;
			//write "✅ [Trip " + trip_id + "] vitesse calculée : " + speed + " m/s pour " + dist + "m en " + duration + "s";
		}
			
        }
        
        if (trip_id = 2096254){write "speed: "+ speed + "time_diff: " + time_diff + "distance diff: " + distance_diff;}
    }
}


	reflex move when: not waiting_at_stop and self.location != target_location {
		do goto target: target_location on: local_network speed: speed;
		if location distance_to target_location < 5#m{ location <- target_location;}
	}

	reflex check_arrival when: self.location = target_location and not waiting_at_stop {
    if (current_stop_index < length(departureStopsInfo) - 1) {
        
        // Calcul de l'écart de temps à l'arrivée
        int expected_arrival_time <- departureStopsInfo[current_stop_index].value as int;
        int actual_time <- current_seconds_mod;
        int time_diff_at_stop <- actual_time - expected_arrival_time;
        
        // Ajouter dans la bonne liste
        if (time_diff_at_stop > 0) {
            arrival_time_diffs_pos << time_diff_at_stop; // Retard
        } else {
            arrival_time_diffs_neg << time_diff_at_stop; // Avance
        }

        if (trip_id = 2096254){write "✅ Arrivé au stop " + current_stop_index + " pour trip " + trip_id + 
              " | écart de temps entre " + actual_time + " with current date " +  current_date + " et " + expected_arrival_time + " = " + time_diff_at_stop + " sec.";
              write "departureStopsInfo: " + departureStopsInfo;}

        // Préparer l'étape suivante
        current_stop_index <- current_stop_index + 1;
        target_location <- departureStopsInfo[current_stop_index].key.location;
        waiting_at_stop <- true;
        
    } else {
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
                data "Max Early" value: mean(bus collect mean(each.arrival_time_diffs_pos)) color: # green marker_shape: marker_empty style: spline;
                data "Max Late" value: mean(bus collect mean(each.arrival_time_diffs_neg)) color: # red marker_shape: marker_empty style: spline;
            }
        }
	}
}




