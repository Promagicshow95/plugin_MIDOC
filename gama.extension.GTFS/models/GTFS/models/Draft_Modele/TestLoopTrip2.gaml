/**
* Name: TestLoopTrip2
* Based on the internal empty template. 
* Author: tiend
* Tags: 
*/


model TestLoopTrip2



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
	int shape_id_test;
	list<bus_stop> list_bus_stops;
	map<string, string> trip_first_departure_time;
	map<string,string>trips_id_time;
	globalBusManager manager; 
	string formatted_time;
	 
	date starting_date <- date("2024-02-21T20:55:00");
	float step <- 1#mn;

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
	
		loop bs over: departure_stops {
			map<string, list<pair<bus_stop, string>>> info <- bs.departureStopsInfo;
			global_departure_info <- global_departure_info + info;
		}
		
		
		all_trips_to_launch <- keys(global_departure_info);
		
		loop trip_id over: all_trips_to_launch{
			list<pair<bus_stop, string>> all_trip_global <- global_departure_info[trip_id];
			list<string> list_times <- all_trip_global collect (each.value);
			trips_id_time[trip_id] <- list_times[0];
		}
		
		
		write "list of trip with time: "+trips_id_time;
	}
	
	list<string> sorted_trip_ids <- all_trips_to_launch sort_by (trips_id_time[each]);
	
	reflex update_formatted_time{
	 	int current_hour <- current_date.hour;
        int current_minute <- current_date.minute;
        int current_second <- current_date.second;

        string current_hour_string <- (current_hour < 10 ? "0" + string(current_hour) : string(current_hour));
        string current_minute_string <- (current_minute < 10 ? "0" + string(current_minute) : string(current_minute));
        string current_second_string <- (current_second < 10 ? "0" + string(current_second) : string(current_second));

        formatted_time <- current_hour_string + ":" + current_minute_string + ":" + current_second_string;
	}
	
	reflex launch_buses_dynamic {
		loop trip_id over: sorted_trip_ids where !(trip_id in: launched_trips) {
			if (formatted_time = trips_id_time[trip_id]) {
				write "\ud83d\ude8c Lancement du bus pour trip: " + trip_id + " à l'heure: " + formatted_time;
				
				int shape_found <- -1;
				ask bus_stop where (each.departureStopsInfo != nil) {
					shape_found <- self.tripShapeMap[trip_id] as int;
					if (shape_found != 0) { break; }
				}
				
				shape_id_test <- shape_found;
				shape_network <- as_edge_graph(transport_shape where (each.shapeId = shape_id_test));
				
				list<pair<bus_stop, string>> departureStopsInfo_trip <- global_departure_info[trip_id];
				list_bus_stops <- departureStopsInfo_trip collect (each.key);
				
				create bus {
					departureStopsInfo <- departureStopsInfo_trip;
					current_stop_index <- 0;
					list_bus_stops <- departureStopsInfo_trip collect (each.key);
					location <- list_bus_stops[0].location;
					target_location <- list_bus_stops[1].location;
					trip_id <- int(trip_id);
				}
				add trip_id to: launched_trips;
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
	aspect default { if (shapeId = shape_id_test){ draw shape color: #green; } }
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
	
	init { speed <- 10.0; }
	
	reflex move when: self.location != target_location {
		do goto target: target_location on: shape_network speed: speed;
	}
	
	reflex check_arrival when: self.location = target_location {
		write "\ud83d\udd38 Bus arrivé à: " + list_bus_stops[current_stop_index].stopName;
		if (current_stop_index < length(list_bus_stops) - 1) {
			current_stop_index <- current_stop_index + 1;
			target_location <- list_bus_stops[current_stop_index].location;
		} else {
			write "\u2705 Bus terminé trip " + trip_id;
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


