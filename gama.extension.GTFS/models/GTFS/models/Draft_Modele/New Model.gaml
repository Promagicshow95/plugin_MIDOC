/**
* Name: NewModel
* Based on the internal empty template. 
* Author: tiend
* Tags: 
*/


model NewModel



global {
	gtfs_file gtfs_f <- gtfs_file("../../includes/tisseo_gtfs_v2");
    shape_file boundary_shp <- shape_file("../../includes/boundaryTLSE-WGS84PM.shp");
    shape_file cleaned_road_shp <- shape_file("../../includes/cleaned_network.shp");
    geometry shape <- envelope(boundary_shp);
    graph shape_network; 
    int shape_id;
    int routeType_selected;

    init {
    	write "📥 Chargement des données GTFS...";
        create road from: cleaned_road_shp {
            if (self.shape intersects world.shape) {} else { do die; }
        }
        create bus_stop from: gtfs_f {}
        create transport_trip from: gtfs_f {}
        create transport_shape from: gtfs_f {}
        
        // Sélectionner les stops de départ (routeType = 1 & a des trips)
        list<bus_stop> departure_stops <- bus_stop where (length(each.departureStopsInfo) > 0 and each.routeType = 1);
        write "🚏 Stops de départ trouvés: " + departure_stops;
        
        // Chaque bus_stop lance ses trips
        ask departure_stops {
        	write "🚀 Lancement des trips pour stop: " + self.name;
        	loop trip_id over: keys(self.departureStopsInfo) {
        		int selected_trip_id <- int(trip_id);
        		shape_id <- (transport_trip first_with (each.tripId = selected_trip_id)).shapeId;
        		routeType_selected <- (transport_trip first_with (each.tripId = selected_trip_id)).routeType;
        		list<pair<bus_stop, string>> departureStopsInfo_trip <- self.departureStopsInfo[trip_id];
        		list<bus_stop> list_bus_stops <- departureStopsInfo_trip collect (each.key);
        		
        		create bus {
        			departureStopsInfo <- departureStopsInfo_trip;
        			current_stop_index <- 0;
        			list_bus_stops <- departureStopsInfo_trip collect (each.key);
        			location <- list_bus_stops[0].location;
        			target_location <- list_bus_stops[1].location;
        			trip_id <- selected_trip_id;
        			shape_network <- shape_network;
        			shape_network <- as_edge_graph(transport_shape where (each.shapeId = shape_id));
        		}
        	}
        }
    }
}

species bus_stop skills: [TransportStopSkill] {
	aspect base {
      draw circle(20) color: #blue;
    }
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
	graph shape_network;
	list<bus_stop> list_bus_stops;
	int current_stop_index <- 0;
	point target_location;
	list<pair<bus_stop,string>> departureStopsInfo;
	int trip_id;
	
	aspect base {
        draw rectangle(200, 100) color: #red rotate: heading;
    }
	init { speed <- 15.5; }
	
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
