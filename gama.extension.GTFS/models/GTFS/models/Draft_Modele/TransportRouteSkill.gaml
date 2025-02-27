model TransportRouteSkill

/**
* Name: GestionBusParArret
* Based on the internal empty template. 
* Author: tiend
* Tags: 
*/



global {
	gtfs_file gtfs_f <- gtfs_file("../../includes/tisseo_gtfs_v2");
	shape_file boundary_shp <- shape_file("../../includes/boundaryTLSE-WGS84PM.shp");
	shape_file cleaned_road_shp <- shape_file("../../includes/cleaned_network.shp");
	geometry shape <- envelope(boundary_shp);
	graph road_network;
	bus_stop starts_stop;
	string formatted_time;
	list<string> trip_ids;
	 
	date starting_date <- date("2024-02-21T20:55:00");
	 float step <- 1#mn;
	 init{
	 	write "Loading GTFS contents from: " + gtfs_f;
        create road from: cleaned_road_shp;
        create bus_stop from: gtfs_f {}
        road_network <- as_edge_graph(road);
        starts_stop <- bus_stop[1017];
	 }

	 reflex update_formatted_time{
	 	int current_hour <- current_date.hour;
        int current_minute <- current_date.minute;
        int current_second <- current_date.second;

        string current_hour_string <- (current_hour < 10 ? "0" + string(current_hour) : string(current_hour));
        string current_minute_string <- (current_minute < 10 ? "0" + string(current_minute) : string(current_minute));
        string current_second_string <- (current_second < 10 ? "0" + string(current_second) : string(current_second));

        formatted_time <- current_hour_string + ":" + current_minute_string + ":" + current_second_string;
        
	 }
	 
}

species bus_stop skills: [TransportStopSkill] {
    aspect base {
        draw circle(10) color: #blue;
    }
	list<pair<bus_stop, string>> departureStopsInfo_trip;
	list<bus_stop> list_bus_stops;
	list<string> list_times;
    
 
  bool operation_done <- false;
  
  reflex check_departure_time when: length(departureStopsInfo) > 0 and not operation_done {
        trip_ids <- keys(starts_stop.departureStopsInfo);
        

        loop trip_id over: trip_ids {
            departureStopsInfo_trip <- starts_stop.departureStopsInfo[trip_id];
            list_bus_stops <- departureStopsInfo_trip collect (each.key);
            list_times <- departureStopsInfo_trip collect (each.value);

            if (length(list_bus_stops) > 0 and length(list_times) > 0 and formatted_time >= list_times[0]) {
                write "Création d'un bus pour le trip " + trip_id + " au départ de " + starts_stop.stopName;

                create bus with: [
                    departureStopsInfo::departureStopsInfo_trip,
                    list_bus_stops::list_bus_stops,
                    list_times::list_times,
                    current_stop_index::0,
                    location::list_bus_stops[0].location,
                    target_location::(length(list_bus_stops) > 1 ? list_bus_stops[1].location : nil)
                ];
                // Une fois le bus créé, on désactive le réflexe pour éviter une création multiple
            	operation_done <- true;
            }
        }
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
    list<string> trip_ids;
	int current_stop_index <- 0;
	point target_location;
	list<pair<bus_stop,string>> departureStopsInfo;
	list<string> list_times;
	bool is_waiting <- true;
	
	init {
        speed <- 0.7;
    }
    
     reflex check_departure_time when: is_waiting {
    	if (current_stop_index < length(list_bus_stops)) {
        string departure_time <- list_times[current_stop_index];

        if (formatted_time >= departure_time) {
            is_waiting <- false;
            write "Départ du bus vers " + list_bus_stops[current_stop_index].stopName;
        }
    	} else {
        is_waiting <- false; // Empêche la boucle infinie
    }
}

    
     // Déplacement du bus vers le prochain arrêt
     // Reflexe pour déplacer le bus vers target_location
    reflex move when: self.location != target_location and current_stop_index < length(list_bus_stops) and not is_waiting {
        do goto target: target_location on: road_network speed: speed;
    }
    
   // Reflexe pour vérifier l'arrivée et mettre à jour le prochain arrêt
    reflex check_arrival when: self.location = target_location {
    if (current_stop_index < length(list_bus_stops) - 1) {
        current_stop_index <- current_stop_index + 1;
        target_location <- list_bus_stops[current_stop_index].location;

        is_waiting <- true; // Active l'attente SEULEMENT si le bus n'est pas au dernier arrêt

        write "Bus attend à " + list_bus_stops[current_stop_index - 1].stopName + 
              " jusqu'à " + list_times[current_stop_index];
    } else {
        target_location <- nil;
        write "Bus a atteint le dernier arrêt.";
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




