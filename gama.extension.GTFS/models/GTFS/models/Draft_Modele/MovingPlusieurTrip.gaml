/**
* Name: MovingPlusieurTrip
* Based on the internal empty template. 
* Author: tiend
* Tags: 
*/


model MovingPlusieurTrip

global {
	gtfs_file gtfs_f <- gtfs_file("../../includes/tisseo_gtfs_v2");
	shape_file boundary_shp <- shape_file("../../includes/boundaryTLSE-WGS84PM.shp");
	shape_file cleaned_road_shp <- shape_file("../../includes/cleaned_network.shp");
	 geometry shape <- envelope(boundary_shp);
	 graph shape_network; 
	 list<bus_stop> list_bus_stops;
	 int shape_id;
	 int routeType_selected;
	 list<pair<bus_stop,string>> departureStopsInfo;
	 bool is_bus_running <- false; 
	 list<string> trips_id;
	 list<int> trip_list;
	 int current_trip_index <- 0;
	 int trip_id;
	 bus_stop starts_stop;
	

	 

	 init{
	 	write "Loading GTFS contents from: " + gtfs_f;
        create road from: cleaned_road_shp{
        	if(self.shape intersects world.shape){}
        	else {
        		
        		do die;
        	}
        }
        create bus_stop from: gtfs_f {
        }
        create transport_trip from: gtfs_f{
        }
        create transport_shape from: gtfs_f{
        }
        

		//Creation le réseaux pour faire bouger l'agent bus
     	shape_network <- as_edge_graph(transport_shape where (each.shapeId = shape_id));
     	
     	//Le bus_stop choisit
        starts_stop <- bus_stop[1017];
        
        trips_id <- keys(starts_stop.departureStopsInfo);
        trip_list <- trips_id collect int(each);
		
		
		// Lancer le premier trip
        if (length(trip_list) > 0) {
            do launch_next_trip;
        }

	 }
	 
	  action launch_next_trip{
        	if (current_trip_index < length(trip_list) and not is_bus_running){
        		is_bus_running <- true;  // Bloque le lancement de plusieurs bus en même temps
        		int selected_trip_id <- trip_list[current_trip_index];
        		
        		
        		 // Récupérer le shapeId correspondant au trip en cours
        		 shape_id <- (transport_trip first_with (each.tripId = selected_trip_id)).shapeId;
        		 shape_network <- as_edge_graph(transport_shape where (each.shapeId = shape_id));
        		 
        		  // Récupérer les arrêts associés à ce trip
        		 list<pair<bus_stop, string>> departureStopsInfo_trip <- starts_stop.departureStopsInfo[selected_trip_id];
        		 list_bus_stops <- departureStopsInfo_trip collect (each.key);
        		 
        		 // Créer un bus pour ce trip
            	create bus {
                	departureStopsInfo <- departureStopsInfo_trip;
                	list_bus_stops <- list_bus_stops;
                	current_stop_index <- 0;
                	location <- list_bus_stops[0].location;
                	target_location <- list_bus_stops[1].location;
                	trip_id <- selected_trip_id;  // Stocke l'ID du trip
                	write "🚍 Bus lancé pour le trip: " + selected_trip_id;
            	}
        	}
       }
    
}

species bus_stop skills: [TransportStopSkill] {
    rgb customColor <- rgb(0,0,255); 
	
    aspect base {
      draw circle(20) color: customColor;
    }
}

species transport_trip skills: [TransportTripSkill]{
	  init {
       
    }
	
}

species transport_shape skills: [TransportShapeSkill]{
	init {
     
    }
	aspect default {
        if (shapeId = shape_id){draw shape color: #green;}

    }
   
	
}

species road {
    aspect default {
         if (routeType = 1)  { draw shape color: #black; } 
    }
  
    int routeType; 
    int shapeId;
    string routeId;
}

species bus skills: [moving] {
	 aspect base {
        draw rectangle(200, 100) color: #red rotate: heading;
    }


    list<bus_stop> list_bus_stops;
	int current_stop_index <- 0;
	point target_location;
	list<pair<bus_stop,string>> departureStopsInfo;
	int trip_id;
	
	
	
	init {
        speed <- 3.0;
		
    }
    
    
    
     // Déplacement du bus vers le prochain arrêt
     // Reflexe pour déplacer le bus vers target_location
    reflex move when: self.location != target_location  {
        do goto target: target_location on: shape_network speed: speed;
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
    
     // Fin du trip, lancer le prochain trip
  
}

// Expérience GUI pour visualiser la simulation
experiment GTFSExperiment type: gui {
    output {
        display "Bus Simulation" {
            species bus_stop aspect: base refresh: true;
            species bus aspect: base;
            species road aspect: default;
            species transport_shape aspect:default;
        }
    }
}



