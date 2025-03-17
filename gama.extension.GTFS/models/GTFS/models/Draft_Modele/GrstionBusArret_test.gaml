/**
* Name: GTFSTest
* Based on the internal empty template. 
* Author: tiend
* Tags: 
*/


model GTFSTest

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
    list<string> trips_to_launch;
    bus_stop stop_reference;
    graph local_network;
    
    init{
    	 write "📥 Chargement des données GTFS...";
        create road from: cleaned_road_shp {
            if(self.shape intersects world.shape) {} else { do die; }
        }
        create bus_stop from: gtfs_f {}
        create transport_trip from: gtfs_f {}
        create transport_shape from: gtfs_f {}
        
        
        // Sélectionner les stops de départ (routeType = 1 & a des trips)
        list<bus_stop> departure_stops <- bus_stop where (length(each.departureStopsInfo) > 0 and each.routeType = 1);
        write "list of departure stop of metro:  " + departure_stops;
        
     	 loop bs over: departure_stops {
     	 	create busManager {
     	 	stop_reference <- bs;
            trips_to_launch <- keys(bs.departureStopsInfo);
            write "trip to lauch pour chaque stop: " + stop_reference + trips_to_launch;
     	 }
     	 
     	 }
     	 
  

        
    }
}

species busManager {
	bus_stop stop_reference;
    list<string> trips_to_launch;
    int current_trip_index <- 0;
    bool is_bus_running <- false;
	
	action launch_next_trip {
		if (current_trip_index < length(trips_to_launch) and not is_bus_running){
			is_bus_running <- true;
			int selected_trip_id <- trips_to_launch[current_trip_index] as int;		
			write "🚌 Lancement du trip " + selected_trip_id + " depuis " + stop_reference.name;
			
			routeType_selected <- (transport_trip first_with (each.tripId = selected_trip_id)).routeType;
			
			// Récupération du shapeId et mise à jour du réseau
            shape_id <- (transport_trip first_with (each.tripId = selected_trip_id)).shapeId;
            shape_network <- as_edge_graph(transport_shape where (each.shapeId = shape_id));
            
            // Récupération des arrêts du trip
            list<pair<bus_stop, string>> departureStopsInfo_trip <- stop_reference.departureStopsInfo["" + selected_trip_id];
            write "departureStopsInfo_trip :" + departureStopsInfo_trip;
            list_bus_stops <- departureStopsInfo_trip collect (each.key);
            
            // Création du bus
            create bus {
                departureStopsInfo <- departureStopsInfo_trip;
                current_stop_index <- 0;
                list_bus_stops <- list_bus_stops;
                location <- list_bus_stops[0].location;
                target_location <- list_bus_stops[1].location;
                trip_id <- selected_trip_id;
                manager <- busManager[0];
                local_network <- as_edge_graph(transport_shape where (each.shapeId = shape_id));
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
    
    reflex move when: self.location != target_location {
        do goto target: target_location on: local_network speed: 3.0;
    }
    
     reflex check_arrival when: self.location = target_location {
        if (current_stop_index < length(list_bus_stops) - 1) {
            current_stop_index <- current_stop_index + 1;
            target_location <- list_bus_stops[current_stop_index].location;
        } else {
            do terminate_trip;
        }
    }
    
     action terminate_trip {
        manager.is_bus_running <- false;
        manager.current_trip_index <- manager.current_trip_index + 1;

        if (manager.current_trip_index < length(manager.trips_to_launch)) {
            ask manager { do launch_next_trip; }
        } else {
            write "🎉 Tous les trips sont terminés pour " + manager.stop_reference.name;
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