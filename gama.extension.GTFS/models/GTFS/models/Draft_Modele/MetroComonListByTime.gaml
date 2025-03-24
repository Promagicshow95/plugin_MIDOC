/**
* Name: TestLoopTrip3
* Based on the internal empty template. 
* Author: tiend
* Tags: 
*/


model MetroComonListByTime

global{
	gtfs_file gtfs_f <- gtfs_file("../../includes/tisseo_gtfs_v2");
	shape_file boundary_shp <- shape_file("../../includes/boundaryTLSE-WGS84PM.shp");
	geometry shape <- envelope(boundary_shp);
	graph local_network; 
	graph shape_network;
	graph road_network;
	graph metro_network;
	
	int shape_id;
	int routeType_selected;
	
	map<string, list<pair<bus_stop, string>>> global_departure_info; 
	list<string> all_trips_to_launch;
	int current_trip_index <- 0;
	int shape_id_test;
	list<bus_stop> list_bus_stops;
	map<string, string> trip_first_departure_time;
	map<string, string> sorted_trips_id_time;
	map<string,string>trips_id_time;
	string formatted_time;
	map<string, bool> trips_already_launched;
	list<string> launched_trips;
	
	 
	date starting_date <- date("2024-02-21T20:55:00");
	float step <- 1#mn;
	
	init{

		create bus_stop from: gtfs_f {}
		create transport_shape from: gtfs_f {}
		
		// Liste des bus_stop départ
		list<bus_stop> departure_stops <- bus_stop where (length(each.departureStopsInfo) > 0 and each.routeType = 1);
		write "🚏 Départ stops trouvés: " + departure_stops;
		
		loop bs over: departure_stops {
			map<string, list<pair<bus_stop, string>>> info <- bs.departureStopsInfo;
			global_departure_info <- global_departure_info + info;
		}
		all_trips_to_launch <- keys(global_departure_info);
		//write "all trip to launch: "+ all_trips_to_launch;
		//write "longueur des trips: " + length(all_trips_to_launch);
		
		loop trip_id over: all_trips_to_launch {
			list<pair<bus_stop, string>> all_trip_global <- global_departure_info[trip_id];
			//write "all trip global: " + all_trip_global;
			list<string> list_times <- all_trip_global collect (each.value);
			trips_id_time[trip_id] <- list_times[0];
			trips_already_launched[trip_id] <- false; 
		}
	
		//write "list of trip with time: "+trips_id_time;
		
		list<pair<string, string>> pairs_list <- trips_id_time.pairs;
		pairs_list <- pairs_list sort_by each.value;
		sorted_trips_id_time <- pairs_list as_map (each.key::each.value);
		write "Map trié : " + sorted_trips_id_time;
		
		metro_network <- as_edge_graph(transport_shape where (each.routeType = 1));
	
		
		
	}
	
		reflex update_formatted_time{
	 	int current_hour <- current_date.hour;
        int current_minute <- current_date.minute;
        int current_second <- current_date.second;
        

        string current_hour_string <- (current_hour < 10 ? "0" + string(current_hour) : string(current_hour));
        string current_minute_string <- (current_minute < 10 ? "0" + string(current_minute) : string(current_minute));
        string current_second_string <- (current_second < 10 ? "0" + string(current_second) : string(current_second));

        formatted_time <- current_hour_string + ":" + current_minute_string + ":" + current_second_string;
        
	 }
	 
	 reflex launch_buses_dynamic{
	 	 loop trip_id over: all_trips_to_launch  {
	 	 	if (formatted_time = sorted_trips_id_time[trip_id] and not trips_already_launched[trip_id]){
	 	 		write "Lancement du bus pour trip: " + trip_id + " à l'heure: " + formatted_time;
	 	 		
	 	 		int shape_found <- -1;
				ask bus_stop where (length(each.departureStopsInfo) > 0 and each.routeType = 1) {
					shape_found <- self.tripShapeMap[trip_id] as int;
					if (shape_found != 0) { break; }
				}
				
				shape_id_test <- shape_found;
				local_network <- as_edge_graph(transport_shape where (each.shapeId = shape_id_test));
				
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
				trips_already_launched[trip_id] <- true;
	 	 	}
	 	 }
	 }
}

species bus_stop skills: [TransportStopSkill] {
	rgb customColor <- rgb(0,0,255);
	aspect base { draw circle(20) color: customColor; }
}

species transport_shape skills: [TransportShapeSkill] {
	
	//aspect default { if (shapeId = shape_id_test){ draw shape color: #green; } }
	 aspect default {draw shape color: #black;}
}


species bus skills: [moving] {
	aspect base { draw rectangle(50, 50) color: #red rotate: heading; }
	list<bus_stop> list_bus_stops;
	int current_stop_index <- 0;
	point target_location;
	list<pair<bus_stop,string>> departureStopsInfo;
	int trip_id;
	
	init { speed <- 0.5; }
	
	reflex move when: self.location != target_location {
		do goto target: target_location on: shape_id_test speed: speed;
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
			species transport_shape aspect: default;
		}
	}
}

