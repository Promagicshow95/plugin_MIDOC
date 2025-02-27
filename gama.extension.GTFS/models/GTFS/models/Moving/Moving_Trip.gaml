/**
* Name: test
* Based on the internal empty template. 
* Author: tiend
* Tags: 
*/


model test



global {
	gtfs_file gtfs_f <- gtfs_file("../../includes/tisseo_gtfs_v2");
	shape_file boundary_shp <- shape_file("../../includes/boundaryTLSE-WGS84PM.shp");
	shape_file cleaned_road_shp <- shape_file("../../includes/cleaned_network.shp");
	 geometry shape <- envelope(boundary_shp);
	 graph road_network;
	 
	 init{
	 	write "Loading GTFS contents from: " + gtfs_f;
        create road from: cleaned_road_shp;
        create bus_stop from: gtfs_f {}
        
        road_network <- as_edge_graph(road);
        
        bus_stop starts_stop <- bus_stop[1017];
        
        create bus {
			departureStopsInfo <- starts_stop.departureStopsInfo['trip_1900861'];
			list_bus_stops <- departureStopsInfo collect (each.key);
			current_stop_index <- 0;
			location <- list_bus_stops[0].location;
			target_location <- list_bus_stops[1].location; 
			write "start_location "+ location;
			write "target_location" + target_location;
			write "Bus créé, suivant le trajet GTFS du trip trip_1900861";			
		}
        
	 }
}

species bus_stop skills: [TransportStopSkill] {
    aspect base {
        draw circle(10) color: #blue;
    }
}

species road {
    aspect default {
        draw shape color: #black;
    }
}

species bus skills: [moving] {
	 aspect base {
        draw rectangle(100, 50) color: #red rotate: heading;
    }
    list<bus_stop> list_bus_stops;
	int current_stop_index <- 0;
	point target_location;
	list<pair<bus_stop,string>> departureStopsInfo;
	
	init {
        speed <- 0.5;
    }
    
     // Déplacement du bus vers le prochain arrêt
     // Reflexe pour déplacer le bus vers target_location
    reflex move when: self.location != target_location and current_stop_index < length(list_bus_stops) {
        do goto target: target_location on: road_network speed: speed;
    }
    
   // Reflexe pour vérifier l'arrivée et mettre à jour le prochain arrêt
    reflex check_arrival when: self.location = target_location {
        write "Bus arrivé à : " + list_bus_stops[current_stop_index].stopName;
        
        if (current_stop_index < length(list_bus_stops) - 1) {
            current_stop_index <- current_stop_index + 1;
            target_location <- list_bus_stops[current_stop_index].location;
            write "Prochain arrêt : " + list_bus_stops[current_stop_index].stopName;
        } else {
            write "Bus a atteint le dernier arrêt.";
            target_location <- nil;
        }
    }
}

// Expérience GUI pour visualiser la simulation
experiment GTFSExperiment type: gui {
    output {
        display "Bus Simulation" {
            species bus_stop aspect: base;
            species bus aspect: base;
            species road aspect: default;
        }
    }
}




