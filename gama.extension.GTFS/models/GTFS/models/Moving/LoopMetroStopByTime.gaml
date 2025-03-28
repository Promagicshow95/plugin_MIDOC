model LoopMetroStopByTime

global {
	gtfs_file gtfs_f <- gtfs_file("../../includes/tisseo_gtfs_v2");
	shape_file boundary_shp <- shape_file("../../includes/boundaryTLSE-WGS84PM.shp");
	shape_file cleaned_road_shp <- shape_file("../../includes/cleaned_network.shp");
	geometry shape <- envelope(boundary_shp);
	graph local_network;
	graph metro_network;
	int shape_id;
	int current_seconds_mod;
	
	date starting_date <- date("2024-02-21T20:55:00");
	float step <- 10 #mn;

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

	// Convertir l'heure actuelle en secondes
	int current_total_seconds <- current_hour * 3600 + current_minute * 60 + current_second;

	// Ramener l'heure sur 24h avec modulo
	current_seconds_mod <- current_total_seconds mod 86400;

}
}

species bus_stop skills: [TransportStopSkill] {
	rgb customColor <- rgb(0,0,255);
	list<string> ordered_trip_ids;
	
	map<string, bool> trips_launched; // Suivi des trips déjà lancés
	
	
	init {
		// Initialiser trips_launched
		loop trip_id over: keys(departureStopsInfo) {
			trips_launched[trip_id] <- false;
		}
		
	}
	

	reflex launch_all_vehicles when: (departureStopsInfo != nil ) {
		loop trip_id over: keys(departureStopsInfo) {
			list<pair<bus_stop, string>> trip_info <- departureStopsInfo[trip_id];
			string departure_time <- trip_info[0].value;

			if (current_seconds_mod = int(departure_time) and not trips_launched[trip_id]) {
				int shape_found <- tripShapeMap[trip_id] as int;
				if shape_found != 0 {
					write "🚍 Lancement du " + (routeType = 1 ? "métro" : "bus") + 
					      " trip " + trip_id + " à " + current_seconds_mod + " depuis " + name;

					list<bus_stop> bs_list <- trip_info collect (each.key);
					shape_id <- shape_found;

					create bus {
						departureStopsInfo <- trip_info;
						current_stop_index <- 0;
						location <- bs_list[0].location;
						target_location <- bs_list[1].location;
						trip_id <- int(trip_id);
						route_type <- myself.routeType;
					}

					trips_launched[trip_id] <- true;
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
