model Moving_Trip

global {
	gtfs_file gtfs_f <- gtfs_file("../../includes/tisseo_gtfs_v2");
	shape_file boundary_shp <- shape_file("../../includes/ShapeFileToulouse.shp");
	geometry shape <- envelope(boundary_shp);
	graph shape_network;
	list<bus_stop> list_bus_stops;
	int shape_id;
	int routeType_selected;
	string selected_trip_id <- "2076784";  // Modifié en string, car tripId est une clé de type string
	list<pair<bus_stop,string>> departureStopsInfo;
	bus_stop starts_stop;
	map<int, graph> shape_graphs;
	int current_seconds_mod <- 0;
	date starting_date <- date("2025-06-09T16:00:00");
	float step <- 5 #s;
	
	init {
    create bus_stop from: gtfs_f;
    create transport_shape from: gtfs_f;

    loop s over: transport_shape {
        shape_graphs[s.shapeId] <- as_edge_graph(s);
    }

    starts_stop <- bus_stop[2474];

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

	aspect base {
		draw circle(20) color: customColor;
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
	bool waiting_at_stop <- true;
	list<int> arrival_time_diffs_pos <- [];
	list<int> arrival_time_diffs_neg <- [];

	init {
		write "Bus créé avec my_departureStopsInfo : " + my_departureStopsInfo;
    	departureStopsInfo <- my_departureStopsInfo;
	}

	reflex wait_at_stop when: waiting_at_stop {
		int stop_time <- departureStopsInfo[current_stop_index].value as int;
		if (current_seconds_mod >= stop_time) {
			waiting_at_stop <- false;
		}
	}

	reflex move when: not waiting_at_stop and self.location distance_to target_location > 5#m {
		do goto target: target_location on: shape_network speed: speed;
		if location distance_to target_location < 5#m {
			location <- target_location;
		}
	}

	reflex check_arrival when: self.location = target_location and not waiting_at_stop {
		if (current_stop_index < length(departureStopsInfo) - 1) {
			current_stop_index <- current_stop_index + 1;
			target_location <- departureStopsInfo[current_stop_index].key.location;
			waiting_at_stop <- true;
			int expected_arrival_time <- departureStopsInfo[current_stop_index].value as int;
			int actual_time <- current_seconds_mod;
			int time_diff_at_stop <- expected_arrival_time - actual_time;

			if (time_diff_at_stop > 0) {
				arrival_time_diffs_pos << time_diff_at_stop;
			} else {
				arrival_time_diffs_neg << time_diff_at_stop;
			}
		} else {
			int finish_time <- int(cycle * step / #s);
			int time_ecart <- int(finish_time - start_time);
			write "🛑 Bus trip terminé : durée réelle = " + time_ecart + " s";
			do die;
		}
	}
}

experiment GTFSExperiment type: gui {
	output {
		display "Bus Simulation" {
			species bus_stop aspect: base refresh: true;
			species bus aspect: base;
			species transport_shape aspect:default;
		}
		display monitor {
			chart "Mean arrival time diff" type: series {
				data "Mean Early" value: mean(bus collect mean(each.arrival_time_diffs_pos)) color: #green marker_shape: marker_empty style: spline;
				data "Mean Late" value: mean(bus collect mean(each.arrival_time_diffs_neg)) color: #red marker_shape: marker_empty style: spline;
			}
		}
	}
}
