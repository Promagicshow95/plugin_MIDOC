/**
* Name: TestLoopTrip
* Based on the internal empty template. 
* Author: tiend
* Tags: 
*/


model TestLoopTrip

/**
* Name: MovingPlusieurTrip
* Based on the internal empty template. 
* Author: tiend
* Tags: 
*/


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
	 list<string> list_trip_string;
	 list<int> trip_list_integer;
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
        list_trip_string <- keys(starts_stop.departureStopsInfo);
        trip_list_integer <- list_trip_string collect int(each);
		
		 // Création du `busManager`
        create busManager {
            stop_reference <- starts_stop;
            trips_to_launch <- list_trip_string;
        }
		ask busManager[0]{do launch_next_trip;}
	 }
	 
    
}

// Nouvelle espèce `busManager` qui gère la création des bus
species busManager {
    bus_stop stop_reference;
    list<string> trips_to_launch;
    int current_trip_index <- 0;
    bool is_bus_running <- false;
    
    // Lancer le prochain trip si disponible
    action launch_next_trip {
    	write "🚌 Lancement du trip index " + current_trip_index + " sur " + length(trips_to_launch);
        if (current_trip_index < length(trips_to_launch) and not is_bus_running) {
            is_bus_running <- true;
		
            int selected_trip_id <- trip_list_integer[current_trip_index];
            write "list of trips to lauch in string: " + trips_to_launch;
            
           	write "🚍 Lancement du trip " + selected_trip_id;

           	routeType_selected <- (transport_trip first_with (each.tripId = selected_trip_id)).routeType;
           	write "routeType of tripId selected: " + routeType_selected;
            

            // Récupération du shapeId et mise à jour du réseau
            shape_id <- (transport_trip first_with (each.tripId = selected_trip_id)).shapeId;
            write "shape id for the trip " + selected_trip_id + " is : " + shape_id;
            shape_network <- as_edge_graph(transport_shape where (each.shapeId = shape_id));

            //Récupération des arrêts associés au trip
            list<pair<bus_stop, string>> departureStopsInfo_trip <- stop_reference.departureStopsInfo[""+selected_trip_id];
            write "list of bus stop and thier departuretime: " + departureStopsInfo_trip;
            
            list_bus_stops <- departureStopsInfo_trip collect (each.key);
            write "list of bus stop: " + list_bus_stops;

            // Création du bus
            create bus {
                departureStopsInfo <- departureStopsInfo_trip;
                write "departureStopsInfo_trip in bus: " + departureStopsInfo_trip;
                current_stop_index <- 0;
                list_bus_stops <- departureStopsInfo_trip collect (each.key);
                write "list_bus_stop in bus: " + list_bus_stops;
                location <- list_bus_stops[0].location;
                target_location <- list_bus_stops[1].location;
                trip_id <- selected_trip_id;
                manager <- busManager[0]; // Lien vers le `busManager`
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
         if (routeType = routeType_selected)  { draw shape color: #black; } 
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
	busManager manager; 
	
	
	
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
            do terminate_trip;
           
        }
    }
    
    //Fin du trip, lancement du suivant
      action terminate_trip {
        manager.is_bus_running <- false;
		manager.current_trip_index <- manager.current_trip_index + 1;
		write "➡️ Passage au trip suivant : " + manager.current_trip_index;
		
        if (manager.current_trip_index < length(manager.trips_to_launch)) {
        	 write "🚍 Lancement du trip suivant : " + manager.trips_to_launch[manager.current_trip_index];
            ask manager{do launch_next_trip;}
        } else {
            write "🎉 Tous les trips sont terminés.";
        }
        do die;
    }
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




