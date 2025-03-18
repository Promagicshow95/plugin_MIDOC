/**
* Name: TestLoopTrip
* Based on the internal empty template. 
* Author: tiend
* Tags: 
*/


model TestLoopTrip

global{
	gtfs_file gtfs_f <- gtfs_file("../../includes/tisseo_gtfs_v2");
	shape_file boundary_shp <- shape_file("../../includes/boundaryTLSE-WGS84PM.shp");
	shape_file cleaned_road_shp <- shape_file("../../includes/cleaned_network.shp");
	geometry shape <- envelope(boundary_shp);
	graph shape_network; 
	int shape_id;
	int routeType_selected;
	
	map<string, list<pair<bus_stop, string>>> global_departure_info; 
	list<string> all_trips_to_launch;
	int current_trip_index <- 0;
	list<bus_stop> list_bus_stops;
	globalBusManager manager; 
	
	init{
		create road from: cleaned_road_shp {
			if (self.shape intersects world.shape) {} else { do die; }
		}
		create bus_stop from: gtfs_f {}
		create transport_trip from: gtfs_f {}
		create transport_shape from: gtfs_f {}
		
		// Liste des bus_stop départ
		list<bus_stop> departure_stops <- bus_stop where (length(each.departureStopsInfo) > 0 and each.routeType = 1);
		write "🚏 Départ stops trouvés: " + departure_stops;

		
//		list<map> temp;
//		loop bs over: departure_stops {
//			map<string, list<pair<bus_stop, string>>> info <- bs.departureStopsInfo;
//			add info to: temp; 
//		}
//		write "all of trip: " + temp;

	

	loop bs over: departure_stops {
		map<string, list<pair<bus_stop, string>>> info <- bs.departureStopsInfo;
		global_departure_info <- global_departure_info + info;
	}

	write "🌍 Global departure info: " + global_departure_info;
	
	all_trips_to_launch <- keys(global_departure_info);
	//write "all trip to lauch: " + all_trips_to_launch;
	
	// Créer le manager global
	list<string> trips_to_launch;
	
	create globalBusManager {
		trips_to_launch <- all_trips_to_launch;
		//write "trip to lauch: " + trips_to_launch;
		
		}
	ask globalBusManager[0] { do launch_next_trip; }

	}
	
}

species globalBusManager{
	list<string> trips_to_launch;
	int current_trip_index <- 0;
	bool is_bus_running <- false;
	
	action launch_next_trip{
		if (current_trip_index < length(trips_to_launch) and not is_bus_running) {
			is_bus_running <- true;
			string selected_trip_id <- trips_to_launch[current_trip_index];
			write "🚌 Lancement trip " + selected_trip_id;
			
			routeType_selected <- (transport_trip first_with (each.tripId = int(selected_trip_id))).routeType;
			
			// Récupérer shapeId
			shape_id <- (transport_trip first_with (each.tripId = int(selected_trip_id))).shapeId;
			shape_network <- as_edge_graph(transport_shape where (each.shapeId = shape_id));
			
			// Récupérer les arrêts depuis global_departure_info
			list<pair<bus_stop, string>> departureStopsInfo_trip <- global_departure_info[selected_trip_id];
			write "list of bus stop in trip with time is: " + departureStopsInfo_trip;
			list_bus_stops <- departureStopsInfo_trip collect (each.key);
			write "list bus stop dehors bus: " + list_bus_stops;
			
			// Créer le bus
			create bus {
				departureStopsInfo <- departureStopsInfo_trip;
				write "list of bus_stop in trip with time in bus: " + departureStopsInfo_trip;
				current_stop_index <- 0;
				list_bus_stops <- departureStopsInfo_trip collect (each.key);
                write "list_bus_stop in bus: " + list_bus_stops;
				location <- list_bus_stops[0].location;
				target_location <- list_bus_stops[1].location;
				trip_id <- int(selected_trip_id);
				manager <- globalBusManager[0];
			}
		}
	}
}

species bus_stop skills: [TransportStopSkill] {
	rgb customColor <- rgb(0,0,255);
	aspect base { draw circle(20) color: customColor; }
}

species transport_trip skills: [TransportTripSkill]{ }
species transport_shape skills: [TransportShapeSkill] {
	aspect default { if (shapeId = shape_id){ draw shape color: #green; } }
}
species road {
	aspect default { if (routeType = routeType_selected) { draw shape color: #black; } }
	int routeType; 
	int shapeId;
	string routeId;
}

species bus skills: [moving] {
	aspect base { draw rectangle(200, 100) color: #red rotate: heading; }
	list<bus_stop> list_bus_stops;
	int current_stop_index <- 0;
	point target_location;
	list<pair<bus_stop,string>> departureStopsInfo;
	int trip_id;
	globalBusManager manager;
	
	init { speed <- 30.0; }
	
	reflex move when: self.location != target_location {
		do goto target: target_location on: shape_network speed: speed;
	}
	
	reflex check_arrival when: self.location = target_location {
		write "🟠 Bus arrivé à: " + list_bus_stops[current_stop_index].stopName;
		if (current_stop_index < length(list_bus_stops) - 1) {
			current_stop_index <- current_stop_index + 1;
			target_location <- list_bus_stops[current_stop_index].location;
		} else {
			write "✅ Bus terminé trip " + trip_id;
			do terminate_trip;
		}
	}
	
	action terminate_trip {
		manager.is_bus_running <- false;
		manager.current_trip_index <- manager.current_trip_index + 1;
		if (manager.current_trip_index < length(manager.trips_to_launch)) {
			write "➡️ Passage au trip suivant";
			ask manager { do launch_next_trip; }
		} else {
			write "🎉 Tous les trips terminés !";
		}
		do die;
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