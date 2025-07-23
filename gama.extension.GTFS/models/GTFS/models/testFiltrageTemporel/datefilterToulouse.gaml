// Cas de test où la starting_date est en dehors de la période du GTFS : on choisit le premier jour ayant le même jour de la semaine.
model datefilter

global {
    // Path to the GTFS file
    gtfs_file gtfs_f <- gtfs_file("../../includes/tisseo_gtfs_v2");
     
    shape_file boundary_shp <- shape_file("../../includes/ShapeFileToulouse.shp");
    
    geometry shape <- envelope(boundary_shp);
    
    date min_date_gtfs <- starting_date_gtfs(gtfs_f);
    date max_date_gtfs <- ending_date_gtfs(gtfs_f);

    
    
    // Counters and storage
    int total_stops_with_info <- 0;
    int total_trips <- 0;
    list<string> unique_stops <- [];
    int total_unique_stops <- 0;
    int nombre_stops_depart <- 0;  // NOUVEAU: compteur stops de départ
    map<string, list<pair<string, string>>> departureStopsInfo;

    // Initialization section
    init {
        write "Le premier jour du GTFS = " + min_date_gtfs;
        write "Le dernier jour du GTFS = " + max_date_gtfs;
      
        // Create bus_stop agents from the GTFS data
        create bus_stop from: gtfs_f {
            
        }
       
        ask bus_stop { 
            do customInit; 
        }
        
        // Reset unique stops tracking
        unique_stops <- [];
        
        // Count total trips and unique stops
        ask bus_stop {
            loop tripId over: departureStopsInfo.keys {
                list<pair<string, string>> stopsList <- departureStopsInfo[tripId];
                loop stop over: stopsList {
                    string stop_id <- stop.key;
                    if not (unique_stops contains stop_id) {
                        unique_stops <- unique_stops + stop_id;
                    }
                }
                total_trips <- total_trips + 1;
            }
        }
        
        total_unique_stops <- length(unique_stops);
        
        // Display statistics
        write "Nombre total de trips créés: " + total_trips;
        write "Nombre d'arrêts créés: " + length(bus_stop);
        write "Nombre de stops de départ (departureStopsInfo non null): " + nombre_stops_depart;  // NOUVEAU
        write "Nombre d'arrêts uniques dans departureStopsInfo: " + total_unique_stops;
    }
}

// Species representing each transport stop
species bus_stop skills: [TransportStopSkill] {
    
    action customInit {
        if length(departureStopsInfo) > 0 {
            total_stops_with_info <- total_stops_with_info + 1;
            nombre_stops_depart <- nombre_stops_depart + 1;  // NOUVEAU: incrémenter le compteur
            //write "Bus stop initialized: " + stopId + ", " + stopName + ", location: " + location + ", departureStopsInfo: " + departureStopsInfo;
        }
    }
 
    aspect base {
        draw circle(100.0) at: location color: #blue;    
    }
}

species my_species skills: [TransportStopSkill] {
    reflex check_stops {
        write "Nombre d'arrêts créés: " + length(bus_stop);
    }
    
    aspect base {
        draw circle(100.0) at: location color: #blue;
    }
}

// GUI-based experiment for visualization
experiment GTFSExperiment type: gui {
    //parameter "Starting Date" var: starting_date <- date("2025-06-26T12:42:06");
    
    // Output section to define the display
    output {
        // Display the bus stops on the map
        display "Bus Stops And Envelope" {
            // Draw boundary envelope
            graphics "Boundary" {
                draw shape color: #gray border: #black;
            }
            
            // Display the bus_stop agents on the map
            species bus_stop aspect: base;
            species my_species aspect: base;
        }
        
        // Information monitors
        //monitor "Current Date/Time" value: "2025-06-26T12:42:06" color: #white;
        monitor "Nombre total de trips" value: total_trips;
        monitor "Nombre d'arrêts" value: length(bus_stop);
        monitor "Nombre de stops de départ" value: nombre_stops_depart;  // NOUVEAU
        monitor "Nombre d'arrêts uniques dans departureStopsInfo" value: total_unique_stops;
        
        // Optional: Display detailed information in a separate window
        inspect "Stops Details" value: bus_stop attributes: ["stopId", "stopName", "departureStopsInfo"] type: table;
    }
}