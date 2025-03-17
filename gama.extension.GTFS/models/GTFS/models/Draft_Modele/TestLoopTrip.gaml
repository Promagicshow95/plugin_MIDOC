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
	list<int> all_trips_to_launch;
	int current_trip_index <- 0;
	
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
		
		// Fusionner tous les departureStopsInfo
		global_departure_info <- map([]);
		all_trips_to_launch <- [];
		
		loop bs over: departure_stops {
			map<string, list<pair<bus_stop, string>>> info <- bs.departureStopsInfo;
			write "infor: " + info;
			
			loop t over: info {
				
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
	
	init { speed <- 3.0; }
	
	reflex move when: self.location != target_location {
		do goto target: target_location on: shape_network speed: speed;
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