
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
	 graph shape_network; 
	 list<bus_stop> list_bus_stops;
	 int shape_id;
	 int shape_id_test;
	 int routeType_selected;
	 int selected_trip_id <- 2041191; 
	 list<pair<bus_stop,string>> departureStopsInfo;
	 bus_stop starts_stop;
	 int current_seconds_mod;
	 
	 date starting_date <- date("2024-02-21T00:00:00");
	
	
	
	float step <- 5 #s;
	 
	 
	 
	 
	 

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

        //Récupérer le shapeId correspondant à ce trip
        shape_id <- (transport_trip first_with (each.tripId = selected_trip_id)).shapeId;
        //write "shape id is: " + shape_id;
        //shape_id_test <- (bus_stop first_with (each.tripShapeMap = selected_trip_id)).tripShapeMap[selected_trip_id];
        //write "shape id is: " + shape_id_test;
       	
		
        
    	
        
		//Creation le réseaux pour faire bouger l'agent bus
     	shape_network <- as_edge_graph(transport_shape where (each.shapeId = shape_id));
     	
     	//Le bus_stop choisit
        starts_stop <- bus_stop[1747];
        
      
       map<string, list<pair<bus_stop, string>>> list_trip_bus <- starts_stop.departureStopsInfo;
       write "list_trip_bus" + list_trip_bus;
       
       list<pair<bus_stop, string>> list_bus_time <- list_trip_bus[string(selected_trip_id)];
       write "list_bus_time" + list_bus_time;
       
        
        
        
        
        
        create bus {
			departureStopsInfo <- list_bus_time;
			list_bus_stops <- list_bus_time collect (each.key);
			write "list of bus:" + list_bus_stops;
			current_stop_index <- 0;
			location <- list_bus_stops[0].location;
			target_location <- list_bus_stops[1].location;	
			start_time <- int(cycle * step / #s);  	
				 
		}
		

	 }
	 
	 reflex update_formatted_time {
		int current_hour <- current_date.hour;
		int current_minute <- current_date.minute;
		int current_second <- current_date.second;
//		write "current_date: " + current_date;
//		write "current_hour: "+ current_hour;
//		write "current_minute: " + current_minute;
//		write "current_second: " + current_second;

		int current_total_seconds <- current_hour * 3600 + current_minute * 60 + current_second;
		current_seconds_mod <- current_total_seconds mod 86400;
		
	}
	

	 
    
}

species bus_stop skills: [TransportStopSkill] {
    rgb customColor <- rgb(0,0,255); 
	map<string,string> trip_shape_map;
	
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
	int start_time;
	bool waiting_at_stop <- true;
	list<int> arrival_time_diffs_pos <- []; // Liste des écarts de temps
	list<int> arrival_time_diffs_neg <- [];
	
	
	
	init {
        speed <- 60 #km/#h;
       	 routeType_selected <- (transport_trip first_with (each.tripId = selected_trip_id)).routeType;
       	 //write "route type selected: "+ routeType_selected;

    }
    
    reflex wait_at_stop when: waiting_at_stop {
    int stop_time <- departureStopsInfo[current_stop_index].value as int;
    write "stop_time theorie of bus_stop " + departureStopsInfo[current_stop_index].key.name + " is " + stop_time;
    write "current time of " + departureStopsInfo[current_stop_index].key.name + " is " + current_seconds_mod;

    if (current_seconds_mod >= stop_time) {
        waiting_at_stop <- false;
    }
	}
    
     // Déplacement du bus vers le prochain arrêt
     // Reflexe pour déplacer le bus vers target_location
    reflex move when: not waiting_at_stop and self.location distance_to target_location > 5#m   {
        do goto target: target_location on: shape_network speed: speed;
        if location distance_to target_location < 5#m{ 
			location <- target_location;
		}
        
    }
    
   // Reflexe pour vérifier l'arrivée et mettre à jour le prochain arrêt
    reflex check_arrival when: self.location = target_location and not waiting_at_stop {
        //write "Bus arrivé à : " + list_bus_stops[current_stop_index].stopName;
        
        if (current_stop_index < length(list_bus_stops) - 1) {
            current_stop_index <- current_stop_index + 1;
            target_location <- list_bus_stops[current_stop_index].location;
            write "Prochain arrêt : " + list_bus_stops[current_stop_index].stopName;
            waiting_at_stop <- true;
             // Calcul de l'écart de temps à l'arrivée
	        int expected_arrival_time <- departureStopsInfo[current_stop_index].value as int;
	        int actual_time <- current_seconds_mod;
	        int time_diff_at_stop <- expected_arrival_time - actual_time ;
	        
	        // Ajouter dans la bonne liste
	        if (time_diff_at_stop > 0) {
	            arrival_time_diffs_pos << time_diff_at_stop; // Retard
	        } else {
	            arrival_time_diffs_neg << time_diff_at_stop; // Avance
	        }
        } else {
            //write "Bus a atteint le dernier arrêt.";
            int finish_time <- int(cycle * step / #s);
        	int time_ecart <- int(finish_time - start_time);
        	write "🛑 Bus trip terminé : durée réelle = " + duration + " s";
        	do die;
        }
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
        
         display monitor {
            chart "Mean arrival time diff" type: series
            {
                data "Mean Early" value: mean(bus collect mean(each.arrival_time_diffs_pos)) color: # green marker_shape: marker_empty style: spline;
                data "Mean Late" value: mean(bus collect mean(each.arrival_time_diffs_neg)) color: # red marker_shape: marker_empty style: spline;
            }

//			chart "Mean arrival time diff" type: series 
//			{
//				data "Total bus" value: length(bus);
//			}
        }
        
        
    }
}












