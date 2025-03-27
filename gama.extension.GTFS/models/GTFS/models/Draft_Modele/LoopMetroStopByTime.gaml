model LoopMetroStopByTime

global {
	gtfs_file gtfs_f <- gtfs_file("../../includes/tisseo_gtfs_v2");
	shape_file boundary_shp <- shape_file("../../includes/boundaryTLSE-WGS84PM.shp");
	shape_file cleaned_road_shp <- shape_file("../../includes/cleaned_network.shp");
	geometry shape <- envelope(boundary_shp);
	graph local_network;
	graph metro_network;
	int shape_id;
	string formatted_time;
	
	date starting_date <- date("2024-02-21T20:55:00");
	float step <- 10 #s;

	init {
		write "📥 Chargement des données GTFS...";
		create bus_stop from: gtfs_f {}
		create transport_shape from: gtfs_f {}
		metro_network <- as_edge_graph(transport_shape where (each.routeType =1));
		
	}
	
	
	//Transform currenttime into string 
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
	map<string, list<pair<bus_stop, string>>> global_departure_info; 
	list<string> all_trips_to_launch;
	map<string, bool> trips_launched;            // Suivi des trips lancés
	map<string,string>trips_id_time;
	map<string, string> sorted_trips_id_time;
	int current_trip_index <- 0;                 // Index du prochain trip à vérifier

	init {
		// Initialiser le suivi de tous les trips à false
		loop trip_id over: keys(departureStopsInfo) {
			trips_launched[trip_id] <- false;
		}
		list<bus_stop> departure_stops <- bus_stop where (length(each.departureStopsInfo) > 0);
		loop bs over: departure_stops {
			map<string, list<pair<bus_stop, string>>> info <- bs.departureStopsInfo;
			global_departure_info <- global_departure_info + info;
		}
		write "global_deaparture_info: " + global_departure_info;
		all_trips_to_launch <- keys(global_departure_info);
		loop trip_id over: all_trips_to_launch {
			list<pair<bus_stop, string>> all_trip_global <- global_departure_info[trip_id];
			//write "all trip global: " + all_trip_global;
			list<string> list_times <- all_trip_global collect (each.value);
			trips_id_time[trip_id] <- list_times[0];
			
		}
	
		list<pair<string, string>> pairs_list <- trips_id_time.pairs;
		pairs_list <- pairs_list sort_by each.value;
		sorted_trips_id_time <- pairs_list as_map (each.key::each.value);
		//write "Map trié : " + sorted_trips_id_time;
		
	}

	reflex launch_all_vehicles when: (departureStopsInfo != nil) {
		if (current_trip_index < length(sorted_trips_id_time)) {
			string trip_id <- sorted_trips_id_time.keys()[current_trip_index];
			string departure_time <- sorted_trips_id_time.values()[current_trip_index];

			if (formatted_time = departure_time and not trips_launched[trip_id]) {
				int shape_found <- tripShapeMap[trip_id] as int;
				if shape_found != 0 {
//					write "🚍 Lancement du " + (routeType = 1 ? "métro" : "bus") +
//					      " trip " + trip_id + " à " + formatted_time + " depuis " + name;
					      
					list<pair<bus_stop, string>> trip_info <- departureStopsInfo[trip_id];
					list<bus_stop> bs_list <- trip_info collect (each.key);
					

					create bus {
						departureStopsInfo <- trip_info;
						current_stop_index <- 0;
						location <- bs_list[0].location;
						target_location <- bs_list[1].location;
						trip_id <- int(trip_id);
						route_type <- myself.routeType;
					}

					trips_launched[trip_id] <- true;
					current_trip_index <- current_trip_index + 1; // Avancer le pointeur
				}
			}
		}
	}

	aspect base {
		draw circle(20) color: customColor;
	}
}

species transport_shape skills: [TransportShapeSkill] {
	aspect default { draw shape color: #black; }
	//aspect default { if (shapeId = shape_id){ draw shape color: #green; } }
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
	int route_type;
	
	init { 	
			local_network <- as_edge_graph(transport_shape where (each.shapeId = shape_id));
			if (route_type = 1) { speed <- 35.0 #km/#h; }      // métro
			else if (route_type = 3) { speed <- 17.75 #km/#h; } // bus
			else if (route_type = 0) { speed <- 19.8 #km/#h; } // tram
			else if (route_type = 6) { speed <- 17.75 #km/#h; } // téléphérique
			else { speed <- 20.0 #km/#h; }                     // par défaut
	}
	
	reflex move when: self.location != target_location {
		do goto target: target_location on: local_network speed: speed;
	}
	
	reflex check_arrival when: self.location = target_location {
		if (current_stop_index < length(departureStopsInfo) - 1) {
			current_stop_index <- current_stop_index + 1;
			target_location <- departureStopsInfo[current_stop_index].key().location;
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
			species transport_shape aspect: default;
		}
	}
}
