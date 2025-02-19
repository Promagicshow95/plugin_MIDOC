model GTFSreader

global {
	gtfs_file gtfs_f <- gtfs_file("../includes/tisseo_gtfs_v2");
	shape_file boundary_shp <- shape_file("../includes/boundaryTLSE-WGS84PM.shp");
	 geometry shape <- envelope(boundary_shp);
	 graph road_network;
	 
	 init{
	 	 write "Loading GTFS contents from: " + gtfs_f;
        create transport_shape from: gtfs_f {}
        create bus_stop from: gtfs_f {}
        
        road_network <- as_edge_graph(transport_shape);
        
        bus_stop starts_stop <- bus_stop[1017];
        
        create bus {
			departureStopsInfo <- starts_stop.departureStopsInfo['trip_1900861'];
			list_bus_stops <- departureStopsInfo collect (each.key);
			current_stop_index <- 0;
			start_location <- list_bus_stops[0].location;
			target_location <- list_bus_stops[1].location; 
			write "start_location "+ start_location;
			write "target_location" + target_location;
			write "Bus créé, suivant le trajet GTFS du trip trip_1900861";			
		}
        
	 }
}

species bus_stop skills: [TransportStopSkill] {
    aspect base {
        draw circle(10) at: location color: #blue;
    }
}


species transport_shape skills: [TransportShapeSkill] {
    aspect base {
        draw shape color: #green;
    }
}

species bus skills: [moving] {
	 aspect base {
        draw rectangle(100, 50) color: #red at: location rotate: heading;
    }
    list<bus_stop> list_bus_stops;
	rgb color <- #red;
	int current_stop_index <- 0;
	point start_location;
	point target_location;
	bool has_arrived <- false;
	list<pair<bus_stop,string>> departureStopsInfo;
	
	init {
        speed <- 0.5;
        do move_to_next_stop;
    }
    
     // Déplacement du bus vers le prochain arrêt
    reflex move when: not has_arrived and current_stop_index < length(list_bus_stops) {
        if (self.location != target_location) {
            do goto target: target_location on: road_network speed: speed;
        } else {
            do stop_at_station;
        }
    }
    
    // Définir le prochain arrêt et continuer le trajet
    action move_to_next_stop {
        if (current_stop_index < length(list_bus_stops) - 1) {
            current_stop_index <- current_stop_index + 1;
            target_location <- list_bus_stops[current_stop_index].location;
            has_arrived <- false;
            write "Bus se dirige vers : " + list_bus_stops[current_stop_index].stopName;
        } else {
            write "Bus a atteint le dernier arrêt.";
        }
    }
    
     // Arrêt du bus à un arrêt spécifique
    action stop_at_station {
        write "Bus arrêté à : " + list_bus_stops[current_stop_index].stopName;
        has_arrived <- true;
        do resume_movement;

    }
    
    // Reprendre le mouvement après un arrêt
    action resume_movement {
        has_arrived <- false;
        do move_to_next_stop;
    }
}

// Expérience GUI pour visualiser la simulation
experiment GTFSExperiment type: gui {
    output {
        display "Bus Simulation" {
            species transport_shape aspect: base;
            species bus_stop aspect: base;
            species bus aspect: base;
        }
    }
}


