
model Moving_Trip

/**
* Name: test
* Based on the internal empty template. 
* Author: tiend
* Tags: 
*/





global {
	gtfs_file gtfs_f <- gtfs_file("../../includes/tisseo_gtfs_v2");
	shape_file boundary_shp <- shape_file("../../includes/boundaryTLSE-WGS84PM.shp");
	shape_file cleaned_road_shp <- shape_file("../../includes/cleaned_network.shp");
	 geometry shape <- envelope(boundary_shp);
	 graph other_network;
	 
	 graph tram_network;
	 
	 graph metro_network;
	 
	 graph bus_network;
	 
	 graph real_network;
	 
	
	 
	 init{
	 	write "Loading GTFS contents from: " + gtfs_f;
        create road from: cleaned_road_shp{
        	if(self.shape intersects world.shape){}
        	else {
        		write "Loading GTFS contents from: " + self.shape;
        		do die;
        	}
      
        }
        create bus_stop from: gtfs_f {}
        
        other_network <- as_edge_graph(road where (not (each.routeType in [1,3,0])));
        bus_network <- as_edge_graph(road where (each.routeType = 3));
        tram_network <- as_edge_graph(road where (each.routeType = 0));
        metro_network <- as_edge_graph(road where (each.routeType = 1));
        real_network <- as_edge_graph(road where (each.routeId = 'line:176'));
        
        
        
        
        
        
        bus_stop starts_stop <- bus_stop[23];
        
        create bus {
			departureStopsInfo <- starts_stop.departureStopsInfo['trip_1983234'];
			list_bus_stops <- departureStopsInfo collect (each.key);
			current_stop_index <- 0;
			location <- list_bus_stops[0].location;
			target_location <- list_bus_stops[1].location; 
			write "start_location "+ location;
			write "target_location" + target_location;
			write "Bus créé, suivant le trajet GTFS du trip trip_1983234";			
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
         if (not (routeType in [0,3]))  { draw shape color: #white; }
         if (routeType = 3)  { draw shape color: #blue; }
         if (routeType = 0){ draw shape color: #white; }
         if (routeId ='line:176'){draw shape color: #black;}
         
         
    }
     int routeType; 
     int shapeId;
     string routeId;
}

species bus skills: [moving] {
	 aspect base {
        draw rectangle(300, 200) color: #red rotate: heading;
    }
    list<bus_stop> list_bus_stops;
	int current_stop_index <- 0;
	point target_location;
	list<pair<bus_stop,string>> departureStopsInfo;
	
	init {
        speed <- 0.8;
    }
    
     // Déplacement du bus vers le prochain arrêt
     // Reflexe pour déplacer le bus vers target_location
    reflex move when: self.location != target_location {
        do goto target: target_location on: real_network speed: speed;
        write "en drection de  : " + list_bus_stops[current_stop_index].stopName;
    }
    
   // Reflexe pour vérifier l'arrivée et mettre à jour le prochain arrêt
    reflex check_arrival when: self.location = target_location {
        write "Bus arrivé à : " + list_bus_stops[current_stop_index].stopName;
        write "current_stop_index: " +current_stop_index;
        write "longeur du trajet: " +length(list_bus_stops);
        
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






