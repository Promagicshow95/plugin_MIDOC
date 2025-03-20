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
	 list<string> trips_id;
     map<string,string> trips_id_time;
     bus_stop starts_stop;
     
	 
	 init{
	 	write "Loading GTFS contents from: " + gtfs_f;
        create road from: cleaned_road_shp;
        create bus_stop from: gtfs_f {
        	
        }
        
        road_network <- as_edge_graph(road);
        
        starts_stop <- bus_stop[1017];
        
        
        create bus {
        	trips_id <- keys(starts_stop.departureStopsInfo);
        	//write "on va voir: " +trips_id ;
        	
        	map<string, string> trip_first_departure_time;
       
       		//write "list of trip: " + trips_id;
       		
       		
        	
        
        	
        
        	loop trip_id over: trips_id{
        		list<pair<bus_stop, string>> departureStopsInfo_trip <- starts_stop.departureStopsInfo[trip_id];
        		//write "departureStopsInfo_trip: "+ departureStopsInfo_trip;
     
        		list<string> list_times <- departureStopsInfo_trip collect (each.value);
        		//write "list_time: " + list_times;
        		trips_id_time[trip_id] <- list_times[0];
        		
        		//write "Map des trips avec heures de départ : " + trips_id_time;
        		
        		list_bus_stops <- departureStopsInfo_trip collect (each.key);
      		
        	}
        	
        	write "trip_id_time: " + trips_id_time;
        	
        	
        	// Trier les trips par heure de départ (ordre croissant)
			list<string> sorted_trip_ids <- trips_id sort_by (trips_id_time[each]);
			//write "Trips triés par heure de départ : " + sorted_trip_ids;
		
			location <- list_bus_stops[0].location;
			target_location <- list_bus_stops[1].location; 
			
					
		}
        
	 }
}

species bus_stop skills: [TransportStopSkill] {
	list<pair<string,string>> sortedTripDeparturesTimes;
	
    aspect base {
        draw circle(10) color: #blue;
    }
    
    
}

species road {
    aspect default {
        draw shape color: #black;
    }
    int routeType; 
}

species bus skills: [moving] {
	 aspect base {
        draw rectangle(100, 50) color: #red at: location rotate: heading;
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




