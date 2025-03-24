model TestLoopTrip4

global {
	gtfs_file gtfs_f <- gtfs_file("../../includes/tisseo_gtfs_v2");
	shape_file boundary_shp <- shape_file("../../includes/boundaryTLSE-WGS84PM.shp");
	shape_file cleaned_road_shp <- shape_file("../../includes/cleaned_network.shp");
	geometry shape <- envelope(boundary_shp);
	graph local_network;
	int shape_id;
	int routeType_selected;
	string formatted_time;
	
	date starting_date <- date("2024-02-21T20:55:00");
	float step <- 0.5#mn;

	init {
		write "📥 Chargement des données GTFS...";
		create bus_stop from: gtfs_f {}
		create transport_shape from: gtfs_f {}
	}
	
	reflex update_formatted_time {
		int current_hour <- current_date.hour;
		int current_minute <- current_date.minute;
		int current_second <- current_date.second;

		string current_hour_string <- (current_hour < 10 ? "0" + string(current_hour) : string(current_hour));
		string current_minute_string <- (current_minute < 10 ? "0" + string(current_minute) : string(current_minute));
		string current_second_string <- (current_second < 10 ? "0" + string(current_second) : string(current_second));

		formatted_time <- current_hour_string + ":" + current_minute_string + ":" + current_second_string;
	}
}

species bus_stop skills: [TransportStopSkill] {
	rgb customColor <- rgb(0,0,255);
	
	map<string, bool> trips_launched; // Suivi des trips déjà lancés
	
	init {
		// Initialiser trips_launched
		loop trip_id over: keys(departureStopsInfo) {
			trips_launched[trip_id] <- false;
		}
	}
	

//	reflex launch_metros when: (departureStopsInfo != nil and routeType = 1) {
//		loop trip_id over: keys(departureStopsInfo) {
//			list<pair<bus_stop, string>> trip_info <- departureStopsInfo[trip_id];
//			//write "trip info is: " + trip_info;
//			string departure_time <- trip_info[0].value;
//			//write "first departure time for the trip " + trip_id + " is: " + departure_time;
//			
//			
//			if (formatted_time = departure_time and not trips_launched[trip_id]) {
//				//write "🚍 Lancement du bus pour trip: " + trip_id + " depuis stop: " + self.name + " à " + formatted_time;
//				
//				// Trouver shapeId et routeType via tripShapeMap
//				int shape_found <- self.tripShapeMap[trip_id] as int;
//				//write "the shape id for moving: " + shape_found;
//				shape_id <- shape_found;
//				local_network <- as_edge_graph(transport_shape where (each.shapeId = shape_id));
//				
//				list<bus_stop> bs_list <- trip_info collect (each.key);
//				
//				// Créer le bus
//				create bus {
//					departureStopsInfo <- trip_info;
//					current_stop_index <- 0;
//					list_bus_stops <- bs_list;
//					location <- bs_list[0].location;
//					target_location <- bs_list[1].location;
//					trip_id <- int(trip_id);
//					
//				}
//				trips_launched[trip_id] <- true; // Marquer lancé
//			}
//		}
//		
//	}
	
	reflex launch_buses when: (departureStopsInfo != nil and routeType = 3) {
	loop trip_id over: keys(departureStopsInfo) {
		list<pair<bus_stop, string>> trip_info <- departureStopsInfo[trip_id];
		string departure_time <- trip_info[0].value;
		
		if (formatted_time = departure_time and not trips_launched[trip_id]) {
			write "🚌 Lancement du BUS pour trip: " + trip_id + " depuis stop: " + self.name + " à " + formatted_time;
			
			int shape_found <- self.tripShapeMap[trip_id] as int;
			shape_id <- shape_found;
			local_network <- as_edge_graph(transport_shape where (each.shapeId = shape_id));
			
			list<bus_stop> bs_list <- trip_info collect (each.key);
			
			create bus {
				departureStopsInfo <- trip_info;
				current_stop_index <- 0;
				list_bus_stops <- bs_list;
				location <- bs_list[0].location;
				target_location <- bs_list[1].location;
				trip_id <- int(trip_id);
			}
			
			trips_launched[trip_id] <- true;
		}
	}
}
	
	
	

	aspect base {
		draw circle(20) color: customColor;
	}
}

species transport_trip skills: [TransportTripSkill]{ }

species transport_shape skills: [TransportShapeSkill] {
	aspect default { draw shape color: #black; }
}

species road {
	aspect default {
		if (routeType = routeType_selected) { draw shape color: #black; }
	}
	int routeType;
	int shapeId;
	string routeId;
}

species bus skills: [moving] {
	graph local_network;
	
	aspect base {
		draw rectangle(50, 100) color: #red rotate: heading;
	}
	
	list<bus_stop> list_bus_stops;
	int current_stop_index <- 0;
	point target_location;
	list<pair<bus_stop,string>> departureStopsInfo;
	int trip_id;
	
	init { 	speed <- 0.5;
			local_network <- as_edge_graph(transport_shape where (each.shapeId = shape_id));
	}
	
	reflex move when: self.location != target_location {
		do goto target: target_location on: local_network speed: speed;
	}
	
	reflex check_arrival when: self.location = target_location {
		//write "🟠 Bus arrivé à: " + list_bus_stops[current_stop_index].stopName;
		if (current_stop_index < length(list_bus_stops) - 1) {
			current_stop_index <- current_stop_index + 1;
			target_location <- list_bus_stops[current_stop_index].location;
		} else {
			//write "✅ Bus terminé trip " + trip_id;
			do die;
		}
	}
}

experiment GTFSExperiment type: gui {
	output {
		display "Bus Simulation" {
			species bus_stop aspect: base refresh: true;
			species bus aspect: base;
			species road aspect: default;
			species transport_shape aspect: default;
		}
	}
}
