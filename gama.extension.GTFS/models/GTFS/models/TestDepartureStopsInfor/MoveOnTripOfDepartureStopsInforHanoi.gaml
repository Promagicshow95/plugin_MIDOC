model MoveOnTripOfDepartureStopsInfor

global {
	gtfs_file gtfs_f <- gtfs_file("../../includes/nantes_gtfs");
	shape_file boundary_shp <- shape_file("../../includes/shapeFileNantes.shp");
	geometry shape <- envelope(boundary_shp);
	graph shape_network;
	list<bus_stop> list_bus_stops;
	int shape_id;
	int routeType_selected;
	string selected_trip_id <- "2039311"; // Modifié en string, car tripId est une clé de type string
	list<pair<bus_stop,string>> departureStopsInfo;
	bus_stop starts_stop;
	map<int, graph> shape_graphs;
	int current_seconds_mod <- 0;
	date starting_date <- date("2018-01-01T16:00:00");
	float step <- 0.2 #s;

	init {
		create bus_stop from: gtfs_f;
		create transport_shape from: gtfs_f;

		loop s over: transport_shape {
			shape_graphs[s.shapeId] <- as_edge_graph(s);
		}

		starts_stop <- bus_stop[0];

		shape_id <- starts_stop.tripShapeMap[selected_trip_id];
		write "Shape id récupéré directement : " + shape_id;

		shape_network <- shape_graphs[shape_id];

		list<pair<bus_stop, string>> stops_for_trip <- starts_stop.departureStopsInfo[selected_trip_id];
		list_bus_stops <- stops_for_trip collect (each.key);
		write "Liste des arrêts du bus : " + list_bus_stops;
		write "DepartureStopsInfo à donner au bus : " + stops_for_trip;
		write "Taille de la liste : " + length(stops_for_trip);

		create bus with: [
			my_departureStopsInfo:: stops_for_trip,
			current_stop_index:: 0,
			location:: list_bus_stops[0].location,
			target_location:: list_bus_stops[1].location,
			start_time:: int(cycle * step / #s)
		];
	}
}

species bus_stop skills: [TransportStopSkill] {
	rgb customColor <- rgb(0,0,255);
	map<string, int> tripShapeMap; // Clé=tripId, Valeur=shapeId
	string name; // Nom de l'arrêt
	bool is_on_selected_trip <- false; // Indique si cet arrêt fait partie du trip sélectionné

	aspect base {
		draw circle(20) color: customColor;
		// Afficher le nom de l'arrêt s'il fait partie du trip sélectionné
		if (is_on_selected_trip and name != nil) {
			draw name color: #black font: font("Arial", 12, #bold) at: location + {0, 25};
		}
	}
}

species transport_shape skills: [TransportShapeSkill]{
	aspect default {
		if (shapeId = shape_id){draw shape color: #green;}
	}
}

species bus skills: [moving] {
	aspect base {
		draw rectangle(200, 100) color: #red rotate: heading;
	}

	list<pair<bus_stop, string>> my_departureStopsInfo;
	int current_stop_index <- 0;
	point target_location;
	int start_time;
	float speed <- 10.0 #km/#h;  // Vitesse du bus (ajustez la valeur)

	init {
		write "Bus créé avec my_departureStopsInfo : " + my_departureStopsInfo;
		departureStopsInfo <- my_departureStopsInfo;
	}

	reflex move when: self.location distance_to target_location > 5#m {
		do goto target: target_location on: shape_network speed: 5.0 #km/#h;
		if location distance_to target_location < 5#m {
			location <- target_location;
		}
	}

	reflex check_arrival when: self.location = target_location {
		// Afficher le nom de l'arrêt où le bus est arrivé
		string stop_name <- departureStopsInfo[current_stop_index].key.name;
		write "Bus arrivé à l'arrêt : " + stop_name + " (index: " + current_stop_index + ")";
		
		if (current_stop_index < length(departureStopsInfo) - 1) {
			current_stop_index <- current_stop_index + 1;
			target_location <- departureStopsInfo[current_stop_index].key.location;
			
			// Afficher le prochain arrêt
			string next_stop_name <- departureStopsInfo[current_stop_index].key.name;
			write "Bus se dirige vers : " + next_stop_name;
		} else {
			write "Bus arrivé au terminus !";
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