/**
 * Name: TestUnicityGTFS
 * Description: Modèle de test d'unicité des agents GTFS dans GAMA
 * Author: tien dat hoang
 * Date: 2025-06-27
 */

model VerificationDesAgents

global {
    // --- Paramètres d'entrée ---
    gtfs_file gtfs_f <- gtfs_file("../../includes/nantes_gtfs"); 
    date starting_date <- date("2025-06-17T00:00:00");

    // --- Création des agents ---
    init {
        create bus_stop from: gtfs_f;
        create transport_shape from: gtfs_f;
    }

    // ---------------------------
    // --- TESTS D'UNICITÉ GTFS
    // ---------------------------
    reflex test_unique_bus_stop when: cycle = 2 {
        int nb_stops <- length(bus_stop);
        list<string> stop_ids <- bus_stop collect each.stopId;
        int nb_stops_unique <- length(remove_duplicates(stop_ids));
        write "--- [TEST] Bus_Stop ---";
        write "Nombre d'agents bus_stop : " + nb_stops;
        write "Nombre de stopId uniques : " + nb_stops_unique;
        if (nb_stops != nb_stops_unique) {
            write "❌ Doublons détectés dans bus_stop !";
        } else {
            write "✅ Aucun doublon de stop_id dans bus_stop.";
        }
    }

    reflex test_unique_trip when: cycle = 2 {
        list<string> all_trip_ids <- [];
        loop bs over: bus_stop {
            if (bs.departureStopsInfo != nil) {
                all_trip_ids <- all_trip_ids + (bs.departureStopsInfo.keys);
            }
        }
        int nb_trip_ids <- length(all_trip_ids);
        int nb_trip_ids_unique <- length(remove_duplicates(all_trip_ids));
        write "--- [TEST] Trips ---";
        write "Nombre total de trip_id dans departureStopsInfo : " + nb_trip_ids;
        write "Nombre de trip_id uniques : " + nb_trip_ids_unique;
        if (nb_trip_ids != nb_trip_ids_unique) {
            write "❌ Doublons de trip_id détectés dans les plannings !";
        } else {
            write "✅ Aucun doublon de trip_id dans les plannings bus_stop.";
        }
    }

    reflex test_unique_shape when: cycle = 2 {
        int nb_shapes <- length(transport_shape);
        list<int> shape_ids <- transport_shape collect each.shapeId;
        int nb_shape_ids_unique <- length(remove_duplicates(shape_ids));
        write "--- [TEST] Shapes ---";
        write "Nombre d'agents transport_shape : " + nb_shapes;
        write "Nombre de shapeId uniques : " + nb_shape_ids_unique;
        if (nb_shapes != nb_shape_ids_unique) {
            write "❌ Doublons détectés dans transport_shape !";
        } else {
            write "✅ Aucun doublon de shapeId dans transport_shape.";
        }
    }

    reflex test_unique_stop_in_planning when: cycle = 2 {
        bool doublon <- false;
        write "--- [TEST] Stops dans chaque trip ---";
        loop bs over: bus_stop {
            if (bs.departureStopsInfo != nil) {
                loop tid over: bs.departureStopsInfo.keys {
                    list<pair<bus_stop, string>> stops <- bs.departureStopsInfo[tid];
                    if (stops != nil and length(stops) > 0) {
                        list<string> stop_ids_in_trip <- stops collect each.key.stopId;
                        int nb_stops <- length(stop_ids_in_trip);
                        int nb_stops_unique <- length(remove_duplicates(stop_ids_in_trip));
                        if (nb_stops != nb_stops_unique) {
                            write "❌ Doublons de stop dans trip " + tid + " du bus_stop " + bs.stopId;
                            doublon <- true;
                        }
                    }
                }
            }
        }
        if (!doublon) {
            write "✅ Aucun doublon de stop dans les trips des bus_stop.";
        }
    }

    reflex recap_GAMA_GTFS when: cycle = 2 {
        write "--- [INFO] Récapitulatif objets GTFS ---";
        write "Nombre de bus_stop : " + length(bus_stop);
        write "Nombre de transport_shape : " + length(transport_shape);
        
        int total_trips <- 0;
        loop bs over: bus_stop {
            if (bs.departureStopsInfo != nil) {
                total_trips <- total_trips + length(bs.departureStopsInfo.keys);
            }
        }
        write "Nombre total de trips dans les bus_stop : " + total_trips;
    }
}

// Espèces minimalistes
species bus_stop skills: [TransportStopSkill]{
    string stopId;
    map<string, list<pair<bus_stop, string>>> departureStopsInfo;
    
    aspect base { 
        draw circle(15) color: #blue; 
    }
}

species transport_shape skills: [TransportStopSkill]{
    int shapeId;
    
    aspect base { 
        draw shape color: #black; 
    }
}

experiment main type: gui autorun: true {
    output {
        display "GTFS" {
            species bus_stop aspect: base;
            species transport_shape aspect: base;
        }
    }
}