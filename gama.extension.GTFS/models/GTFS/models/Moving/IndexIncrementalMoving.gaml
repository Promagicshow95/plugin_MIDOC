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

	date starting_date <- date("2024-02-21T20:55:00");
	float step <- 1 #mn;

	init {
		write "\ud83d\uddd3\ufe0f Chargement des donn\u00e9es GTFS...";
		create bus_stop from: gtfs_f {
		}
		create transport_shape from: gtfs_f {}
		
		// Prégénérer tous les graphes par shapeId
		loop s over: transport_shape {
			shape_graphs[s.shapeId] <- as_edge_graph(s);
		}
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
	map<string, bool> trips_launched;
	list<string> ordered_trip_ids;
	int current_trip_index <- 0;
	bool initialized <- false;

	init {
		loop trip_id over: keys(departureStopsInfo) {
			trips_launched[trip_id] <- false;
		}
		
		
	}  
	
	reflex init_test when: cycle =1{
		loop trip_id over: keys(departureStopsInfo) {
			trips_launched[trip_id] <- false;
		}
		ordered_trip_ids <- keys(departureStopsInfo);
		if (ordered_trip_ids !=nil) {write "ordered_trip_ids: " + ordered_trip_ids;}
		}
	
	
	reflex launch_all_vehicles when: (departureStopsInfo != nil and current_trip_index < length(ordered_trip_ids)){
		string trip_id <- ordered_trip_ids[current_trip_index];
		//write "trip id: " + trip_id ;
		list<pair<bus_stop, string>> trip_info <- departureStopsInfo[trip_id];
		string departure_time <- trip_info[0].value;
		if departure_time = "24:00:00"{departure_time <- "00:00:00";}
		
		if (formatted_time = departure_time ){
		
			int shape_found <- tripShapeMap[trip_id] as int;
			
			if shape_found != 0{
				shape_id <- shape_found;
				
				create bus {
					departureStopsInfo <- trip_info;
					current_stop_index <- 0;
					location <- trip_info[0].key.location;
					target_location <- trip_info[1].key.location;
					trip_id <- int(trip_id);
					route_type <- myself.routeType;
					local_network <- shape_graphs[shape_id];// Utilise le graphe préchargé
				}
				
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

	int current_stop_index <- 0;
	point target_location;
	list<pair<bus_stop,string>> departureStopsInfo;
	int trip_id;
	int route_type;

	init {
		if (route_type = 1) { speed <- 35.0 #km/#h; }
		else if (route_type = 3) { speed <- 17.75 #km/#h; }
		else if (route_type = 0) { speed <- 19.8 #km/#h; }
		else if (route_type = 6) { speed <- 17.75 #km/#h; }
		else { speed <- 20.0 #km/#h; }
	}

	reflex move when: self.location != target_location {
		do goto target: target_location on: local_network speed: speed;
	}

	reflex check_arrival when: self.location = target_location {
		if (current_stop_index < length(departureStopsInfo) - 1) {
			current_stop_index <- current_stop_index + 1;
			target_location <- departureStopsInfo[current_stop_index].key().location;
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
	}
}


