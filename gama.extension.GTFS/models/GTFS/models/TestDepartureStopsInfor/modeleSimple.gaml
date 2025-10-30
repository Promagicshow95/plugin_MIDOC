model MoveOnTripSimple

global {
    // Path to the GTFS file
    string gtfs_f_path;
    string boundary_shp_path;
    date starting_date;

    gtfs_file gtfs_f <- gtfs_file(gtfs_f_path);
    shape_file boundary_shp <- shape_file(boundary_shp_path);
    geometry shape <- envelope(boundary_shp);
    float step <- 0.2 #s;
    
    // Variables GTFS
    string selected_trip_id <- "";
    int selected_bus_stop;
    bus_stop starts_stop;
    list<bus_stop> list_bus_stops;
    string shape_id;

    init {
        write "=== MODÈLE SIMPLE DE DÉPLACEMENT ===";
        
        create bus_stop from: gtfs_f;
        create transport_shape from: gtfs_f;
        
        write "1. Données GTFS chargées: " + string(length(transport_shape)) + " shapes";

        // Configuration trip
        starts_stop <- bus_stop[selected_bus_stop];
        write "2. Configuration trip " + selected_trip_id;

        if (selected_trip_id in starts_stop.tripShapeMap.keys and 
            selected_trip_id in starts_stop.departureStopsInfo.keys) {
            
            shape_id <- starts_stop.tripShapeMap[selected_trip_id];            
            write "   Shape ID: " + string(shape_id);
            
            // Configuration arrêts
            list<pair<bus_stop, string>> stops_for_trip <- starts_stop.departureStopsInfo[selected_trip_id];
            list_bus_stops <- stops_for_trip collect (each.key);
            
            loop i from: 0 to: length(list_bus_stops) - 1 {
                bus_stop stop <- list_bus_stops[i];
                stop.is_in_selected_trip <- true;
                stop.stop_order <- i;
            }

            // Créer bus
            if (length(list_bus_stops) >= 2) {
                create bus with: [
                    my_stops:: list_bus_stops,
                    current_index:: 0,
                    location:: list_bus_stops[0].location,
                    next_target:: list_bus_stops[1].location,
                    at_terminus:: false
                ];
                write "3. Bus créé";
            }
        } else {
            write "✗ Trip non valide";
        }
        
        write "=== DÉMARRAGE SIMULATION ===";
    }
}

species bus_stop skills: [TransportStopSkill] {
    map<string, string> tripShapeMap;
    string name;
    bool is_in_selected_trip <- false;
    int stop_order <- -1;
    
    aspect base {
        if (is_in_selected_trip) {
            draw circle(25) color: #blue;
            if (stop_order >= 0) {
                draw string(stop_order + 1) color: #white font: font("Arial", 12, #bold) at: location;
            }
        }
    }
}

species transport_shape skills: [TransportShapeSkill] {
    aspect default {
        if (shapeId = shape_id) {
            draw shape color: #purple width: 6;
        } else {
            draw shape color: #gray width: 1;
        }
    }
}

species bus skills: [moving] {
    list<bus_stop> my_stops;
    int current_index <- 0;
    point next_target;
    bool at_terminus <- false;
    float speed <- 1.0 #km/#h;
    float total_distance_traveled <- 0.0;
    
    // Variables pour temps d'arrêt
    bool waiting_at_stop <- false;
    int waiting_time <- 5;
    int time_at_stop <- 0;
    
    // Variable pour réseau
    graph my_network;
    
    init {
        // Récupérer la polyline du trip avec first_with (simplifié)
        transport_shape chosen_transport_shape <- transport_shape first_with(each.shapeId = shape_id);
        // Créer réseau pour navigation (sans stocker travel_points)
        my_network <- as_edge_graph([chosen_transport_shape.shape]);
    }

    reflex navigation when: !at_terminus and !waiting_at_stop {
        // Vérifier si on a atteint la cible
        if (location = next_target) {
            // Arrivée à l'arrêt
            waiting_at_stop <- true;
            time_at_stop <- 0;
        } else {
            // Continuer à avancer vers l'arrêt sur le réseau
            point previous_location <- location;
            
            // Navigation sur réseau
            if (my_network != nil) {
                do goto target: next_target on: my_network speed: speed;
            } else {
                do goto target: next_target speed: speed;
            }
            
            total_distance_traveled <- total_distance_traveled + (previous_location distance_to location);
        }
    }
    
    // Reflex pour temps d'arrêt
    reflex wait_at_stop when: waiting_at_stop and !at_terminus {
        time_at_stop <- time_at_stop + 1;
        
        if (time_at_stop >= waiting_time) {
            do arrive_at_stop;
            waiting_at_stop <- false;
        }
    }
    
    // Arriver à un arrêt
    action arrive_at_stop {
        if (current_index >= 0 and current_index < length(my_stops)) {
            bus_stop current_stop <- my_stops[current_index];
            write "🚌 Arrêt " + string(current_index + 1) + "/" + string(length(my_stops)) + ": " + current_stop.name;
            
            current_index <- current_index + 1;
            
            if (current_index < length(my_stops)) {
                next_target <- my_stops[current_index].location;
                write "➡️ Prochain: " + my_stops[current_index].name;
            } else {
                write "🏁 TERMINUS!";
                write "📏 Distance: " + string(round(total_distance_traveled)) + "m";
                at_terminus <- true;
            }
        } else {
            at_terminus <- true;
        }
    }
    
    aspect base {
        rgb bus_color;
        
        if (at_terminus) {
            bus_color <- #orange;
        } else if (waiting_at_stop) {
            bus_color <- #yellow;
        } else {
            bus_color <- #red;
        }
        
        draw rectangle(200, 120) color: bus_color rotate: heading;
        
        string display_text;
        if (at_terminus) {
            display_text <- "TERMINÉ";
        } else if (waiting_at_stop) {
            display_text <- "ARRÊT (" + string(time_at_stop) + "s)";
        } else {
            display_text <- string(current_index + 1) + "/" + string(length(my_stops));
        }
        draw display_text color: #white font: font("Arial", 12, #bold) at: location + {0, -40};
        
        // Vitesse
        if (!at_terminus) {
            draw "V: " + string(round(speed * 3.6)) + "km/h" color: #green 
                 font: font("Arial", 8, #bold) at: location + {0, -60};
        }
        
        // Ligne vers cible
        if (!at_terminus and !waiting_at_stop and next_target != nil) {
            draw line([location, next_target]) color: #blue width: 3;
        }
    }
}

experiment MoveOnTripSimple type: gui virtual: true {
    output {
        display "Navigation Simple" {
            species bus_stop aspect: base;
            species transport_shape aspect: default;
            species bus aspect: base;
        }
        
        monitor "Distance parcourue (m)" value: length(bus) > 0 ? round(first(bus).total_distance_traveled) : 0;
        monitor "Arrêt actuel" value: length(bus) > 0 ? first(bus).current_index + 1 : 0;
        monitor "État bus" value: length(bus) > 0 ? 
            (first(bus).at_terminus ? "Terminus" : 
            (first(bus).waiting_at_stop ? "En arrêt" : "En mouvement")) : "Aucun";
        monitor "Trip ID" value: selected_trip_id;
        monitor "Shape ID" value: shape_id;
    }
}

experiment testSimpleToulouse type: gui parent: MoveOnTripSimple {
    parameter "GTFS file path" var: gtfs_f_path <- "../../includes/tisseo_gtfs_v2";    
    parameter "Boundary shapefile" var: boundary_shp_path <- "../../includes/shapeFileToulouse.shp";
    parameter "Starting date" var: starting_date <- date("2025-06-09T16:00:00");
    
    parameter "Selected Trip ID" var: selected_trip_id <- "2076784";
    parameter "Selected bus stop" var: selected_bus_stop <- 2474;
}

experiment testSimpleNantes type: gui parent: MoveOnTripSimple {
    parameter "GTFS file path" var: gtfs_f_path <- "../../includes/nantes_gtfs";    
    parameter "Boundary shapefile" var: boundary_shp_path <- "../../includes/shapeFileNantes.shp";
    parameter "Starting date" var: starting_date <- date("2025-05-15T00:55:00");
    
    parameter "Selected Trip ID" var: selected_trip_id <- "44958927-CR_24_25-HT25P201-L-Ma-Me-J-11";
    parameter "Selected bus stop" var: selected_bus_stop <- 2540;
}

experiment testSimpleHanoi type: gui parent: MoveOnTripSimple {
    parameter "GTFS file path" var: gtfs_f_path <- "../../includes/hanoi_gtfs_pm";    
    parameter "Boundary shapefile" var: boundary_shp_path <- "../../includes/shapeFileHanoishp.shp";
    parameter "Starting date" var: starting_date <- date("2018-01-01T20:55:00");
    
    parameter "Selected Trip ID" var: selected_trip_id <- "01_1_MD_1";
    parameter "Selected bus stop" var: selected_bus_stop <- 0;
}
