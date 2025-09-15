/**
 * Name: ModeleReseauBusSimple
 * Author: Adapted - Network Only (No JSON Processing)
 * Description: Chargement réseau bus et arrêts uniquement (sans traitement JSON)
 */

model ModeleReseauBusSimple

global {
    // CONFIGURATION FICHIERS
    string results_folder <- "../../results/";
    string stops_folder <- "../../results/stopReseau/";
    
    file data_file <- shape_file("../../includes/shapeFileHanoishp.shp");
    geometry shape <- envelope(data_file);
    
    // VARIABLES STATISTIQUES
    int total_bus_routes <- 0;
    int total_bus_stops <- 0;
    int matched_stops <- 0;
    int unmatched_stops <- 0;
    bool debug_mode <- true;
    
    // STRUCTURES BASIQUES
    map<string, bus_stop> stopId_to_agent;
    map<string, bus_route> osmId_to_route;

    init {
        write "=== RÉSEAU BUS SIMPLE (SANS JSON) ===";
        
        do load_bus_network;
        do load_gtfs_stops;
        do build_basic_mappings;
        
    }
    
    // CHARGEMENT RÉSEAU BUS
    action load_bus_network {
        write "\n1. CHARGEMENT RÉSEAU BUS";
        
        int bus_routes_count <- 0;
        int i <- 0;
        bool continue_loading <- true;
        
        loop while: continue_loading and i < 30 {
            string filename <- results_folder + "bus_routes_part" + i + ".shp";
            
            try {
                file shape_file_bus <- shape_file(filename);
                
                create bus_route from: shape_file_bus with: [
                    route_name::string(read("name")),
                    osm_id::string(read("osm_id")),
                    route_type::string(read("route_type")),
                    highway_type::string(read("highway")),
                    length_meters::float(read("length_m"))
                ];
                
                bus_routes_count <- bus_routes_count + length(shape_file_bus);
                i <- i + 1;
                
                if debug_mode {
                    write "Fichier " + i + " : " + length(shape_file_bus) + " routes";
                }
                
            } catch {
                if debug_mode {
                    write "Fin chargement à l'index : " + i;
                }
                continue_loading <- false;
            }
        }
        
        total_bus_routes <- bus_routes_count;
        write "Routes chargées : " + bus_routes_count;
        
        // Nettoyer les routes sans géométrie
        ask bus_route where (each.shape = nil) {
            do die;
        }
        
        total_bus_routes <- length(bus_route);
        write "Routes avec géométrie valide : " + total_bus_routes;
    }
    
    // CHARGEMENT ARRÊTS GTFS
    action load_gtfs_stops {
        write "\n2. CHARGEMENT ARRÊTS GTFS";
        
        string stops_filename <- stops_folder + "gtfs_stops_complete.shp";
        
        try {
            file shape_file_stops <- shape_file(stops_filename);
            
            create bus_stop from: shape_file_stops with: [
                stopId::string(read("stopId")),
                stop_name::string(read("name")),
                closest_route_id::string(read("closest_id")),
                closest_route_dist::float(read("distance")),
                is_matched_str::string(read("matched"))
            ];
            
            total_bus_stops <- length(shape_file_stops);
            
            // Nettoyer et valider les arrêts
            ask bus_stop {
                is_matched <- (is_matched_str = "TRUE");
                
                if stopId = nil or stopId = "" {
                    stopId <- "stop_" + string(int(self));
                }
                if stop_name = nil or stop_name = "" {
                    stop_name <- "Stop_" + string(int(self));
                }
                
                // Compter les arrêts matchés/non-matchés
                if is_matched {
                    matched_stops <- matched_stops + 1;
                } else {
                    unmatched_stops <- unmatched_stops + 1;
                }
            }
            
            write "Arrêts chargés : " + total_bus_stops;
            write "  - Matchés avec routes OSM : " + matched_stops;
            write "  - Non matchés : " + unmatched_stops;
            
        } catch {
            write "ERREUR : Impossible de charger " + stops_filename;
            write "Vérifiez que le fichier existe et est accessible";
            total_bus_stops <- 0;
        }
    }
    
    // CONSTRUCTION MAPPINGS BASIQUES
    action build_basic_mappings {
        write "\n3. CONSTRUCTION MAPPINGS";
        
        // Mapping stopId -> agent
        stopId_to_agent <- map<string, bus_stop>([]);
        ask bus_stop {
            if stopId != nil and stopId != "" {
                stopId_to_agent[stopId] <- self;
            }
        }
        
        // Mapping osmId -> route
        osmId_to_route <- map<string, bus_route>([]);
        ask bus_route {
            if osm_id != nil and osm_id != "" {
                osmId_to_route[osm_id] <- self;
            }
        }
        
        write "Mappings créés :";
        write "  - stopId -> agent : " + length(stopId_to_agent);
        write "  - osmId -> route : " + length(osmId_to_route);
    }
    
    // APIS D'ACCÈS BASIQUES
    bus_stop get_stop_agent(string stop_id) {
        if stopId_to_agent contains_key stop_id {
            return stopId_to_agent[stop_id];
        }
        return nil;
    }
    
    bus_route get_route_by_osm_id(string osm_id) {
        if osmId_to_route contains_key osm_id {
            return osmId_to_route[osm_id];
        }
        return nil;
    }
    
    list<bus_stop> get_matched_stops {
        return list<bus_stop>(bus_stop where (each.is_matched));
    }
    
    list<bus_stop> get_unmatched_stops {
        return list<bus_stop>(bus_stop where (!each.is_matched));
    }
    
    list<string> get_all_stop_ids {
        return stopId_to_agent.keys;
    }
    
    list<string> get_all_route_osm_ids {
        return osmId_to_route.keys;
    }
    
    // STATISTIQUES RÉSEAU
    
}

// AGENTS
species bus_route {
    string route_name;
    string osm_id;
    string route_type;
    string highway_type;
    float length_meters;
    
    aspect default {
        if shape != nil {
            rgb route_color <- #blue;
            if route_type = "bus" {
                route_color <- #blue;
            } else if route_type = "tram" {
                route_color <- #orange;
            } else if route_type = "subway" {
                route_color <- #purple;
            } else {
                route_color <- #gray;
            }
            draw shape color: route_color width: 2;
        }
    }
    
    aspect detailed {
        if shape != nil {
            rgb route_color <- #blue;
            if route_type = "bus" {
                route_color <- #blue;
            } else if route_type = "tram" {
                route_color <- #orange;
            } else if route_type = "subway" {
                route_color <- #purple;
            } else {
                route_color <- #gray;
            }
            draw shape color: route_color width: 3;
            
        
        }
    }
}

species bus_stop {
    string stopId <- "";
    string stop_name <- "";
    string closest_route_id <- "";
    float closest_route_dist <- -1.0;
    bool is_matched <- false;
    string is_matched_str <- "FALSE";
    
    aspect default {
        rgb stop_color <- is_matched ? #green : #red;
        draw circle(100.0) color: stop_color;
        
     
    }
    
    aspect detailed {
        rgb stop_color <- is_matched ? #green : #red;
        draw circle(120.0) color: stop_color;
        
        if is_matched {
            draw circle(160.0) border: #darkgreen width: 2;
        }
        
        if stop_name != nil and stop_name != "" {
            draw stop_name at: location + {0, 200} color: #black size: 10;
        }
        
        if stopId != nil and stopId != "" {
            draw stopId at: location + {0, -200} color: #gray size: 8;
        }
        
        if is_matched and closest_route_dist > 0 {
            draw string(int(closest_route_dist)) + "m" at: location + {0, 220} color: #blue size: 8;
        }
    }
    
    aspect minimal {
        rgb stop_color <- is_matched ? #green : #red;
        draw circle(80.0) color: stop_color;
    }
}

// EXPERIMENT
experiment network_simple type: gui {
    
    action reload_network {
        ask world {
            ask bus_route { do die; }
            ask bus_stop { do die; }
            
            total_bus_routes <- 0;
            total_bus_stops <- 0;
            matched_stops <- 0;
            unmatched_stops <- 0;
            
            stopId_to_agent <- map<string, bus_stop>([]);
            osmId_to_route <- map<string, bus_route>([]);
            
            do load_bus_network;
            do load_gtfs_stops;
            do build_basic_mappings;
           
        }
    }
    
    user_command "Recharger" action: reload_network;
    
    output {
        display "Réseau Bus" background: #white type: 2d {
            species bus_route aspect: default;
            species bus_stop aspect: default;
        }
    }
}