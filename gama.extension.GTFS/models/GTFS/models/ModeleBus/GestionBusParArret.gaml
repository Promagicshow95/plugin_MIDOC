/**
* Name: GestionBusParArret
* Based on the internal empty template. 
* Author: tiend
* Tags: 
*/


model GestionBusParArret

global {
	gtfs_file gtfs_f <- gtfs_file("../../includes/tisseo_gtfs_v2");
	shape_file boundary_shp <- shape_file("../../includes/boundaryTLSE-WGS84PM.shp");
	shape_file cleaned_road_shp <- shape_file("../../includes/cleaned_network.shp");
	 geometry shape <- envelope(boundary_shp);
	 graph road_network;
	 date starting_date <- date("2024-02-21T20:55:00");
	 float step <- 1#mn;
	 
	
	 init{
	 	write "Loading GTFS contents from: " + gtfs_f;
	 	
        create road from: cleaned_road_shp;
        create bus_stop from: gtfs_f {
        
        }
       
        
        road_network <- as_edge_graph(road);
        
        bus_stop starts_stop <- bus_stop[1017];
        
        int current_hour <- current_date.hour;
		int current_minute <- current_date.minute;
		int current_second <- current_date.second;
		
		string current_hour_string;
			if (current_hour < 10) {
    		current_hour_string <- "0" + string(current_hour);
			} else {
    		current_hour_string <- string(current_hour);
			}

			string current_minute_string;
			if (current_minute < 10) {
    		current_minute_string <- "0" + string(current_minute);
			} else {
    		current_minute_string <- string(current_minute);
			}

			string current_second_string;
			if (current_second < 10) {
    		current_second_string <- "0" + string(current_second);
			} else {
    		current_second_string <- string(current_second);
			}
			
			string formatted_time <- current_hour_string + ":" + current_minute_string + ":" + current_second_string;
			write "formatted_time: " + formatted_time; // Affiche l'heure au format "HH:mm:ss"
        
		

        
	 }
}

species bus_stop skills: [TransportStopSkill] {
    aspect base {
        draw circle(10) color: #blue;
    }
    string formatted_time;
    
    reflex check_departure_time {
    	
			
			list<pair<bus_stop, string>> trip_info <- departureStopsInfo['trip_1900861'];
            list<bus_stop> list_bus_stops <- trip_info collect (each.key);
            list<string> list_times <- trip_info collect (each.value);
            
            // Créer le bus si l'heure actuelle atteint l'heure de départ
            if (length(list_bus_stops) > 0 and formatted_time >= list_times[0]) {
                write "Création d'un bus au départ de " + stopName;
                create bus with: [
                    departureStopsInfo::trip_info,
                    list_bus_stops::list_bus_stops,
                    list_times::list_times,
                    current_stop_index::0,
                    location::list_bus_stops[0].location,
                    target_location::list_bus_stops[1].location
                ];
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
        draw rectangle(100, 50) color: #red at: location rotate: heading;
    }

    list<bus_stop> list_bus_stops;
    list<string> list_times;
    int current_stop_index <- 0;
    point target_location;
    list<pair<bus_stop, string>> departureStopsInfo;
    bool is_waiting <- true;
    string formatted_time;

    init {
        speed <- 0.5;
    }

    // Vérifier l'heure de départ du prochain arrêt avant de bouger
    reflex check_departure_time when: is_waiting {
        string departure_time <- list_times[current_stop_index];

        if (formatted_time >= departure_time) {
            is_waiting <- false;
            write "Départ du bus vers " + list_bus_stops[current_stop_index].stopName;
        }
    }

    // Déplacement du bus vers le prochain arrêt
    reflex move when: target_location != nil and not is_waiting {
        do goto target: target_location on: road_network speed: speed;
    }

    // Vérifier l'arrivée et mettre à jour `target_location`
    reflex check_arrival when: self.location = target_location {
        write "Bus arrivé à " + list_bus_stops[current_stop_index].stopName;

        if (current_stop_index < length(list_bus_stops) - 1) {
            current_stop_index <- current_stop_index + 1;
            target_location <- list_bus_stops[current_stop_index].location;
            is_waiting <- true; // Le bus attend l'heure de départ du prochain arrêt
            write "Bus attend à " + list_bus_stops[current_stop_index - 1].stopName + " jusqu'à " + list_times[current_stop_index];
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




