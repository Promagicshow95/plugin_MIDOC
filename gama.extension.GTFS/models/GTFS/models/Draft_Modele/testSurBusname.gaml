/**
 * Model: osm_transport_networks
 * Author: Promagicshow95
 * Date: 2025-06-12 14:33:25
 */

model osm_transport_networks

global {
    point top_left <- CRS_transform({0,0}, "EPSG:4326").location;
    point bottom_right <- CRS_transform({shape.width, shape.height}, "EPSG:4326").location;
    string adress <- "http://overpass-api.de/api/xapi_meta?*[bbox=" + top_left.x + "," + bottom_right.y + "," + bottom_right.x + "," + top_left.y + "]";
            
    file<geometry> osm_geometries <- osm_file<geometry>(adress, osm_data_to_generate);
    file data_file <- shape_file("../../includes/stops_points_wgs84.shp");
    geometry shape <- envelope(data_file);

    map<string, list> osm_data_to_generate <- [
        "highway"::[], 
        "railway"::[], 
        "route"::[], 
        "cycleway"::[]
    ];
    
    gtfs_file gtfs_f <- gtfs_file("../../includes/hanoi_gtfs_pm");
    shape_file boundary_shp <- shape_file("../../includes/envelopFile/routes.shp");
    
    // Statistiques globales
    int nb_bus_routes <- 0;
    int nb_tram_routes <- 0;
    int nb_subway_routes <- 0;
    
    init {
        // Créer les arrêts de bus depuis GTFS
        create bus_stop from: gtfs_f;
        
        // Créer les routes depuis OSM
        do create_transport_routes;
        
        // Calculer les statistiques
        nb_bus_routes <- network_route count (each.route_type = "bus");
        nb_tram_routes <- network_route count (each.route_type = "tram");
        nb_subway_routes <- network_route count (each.route_type = "subway");
        
        write "Création terminée :";
        write "- " + nb_bus_routes + " routes de bus";
        write "- " + nb_tram_routes + " lignes de tram";
        write "- " + nb_subway_routes + " lignes de métro";
    }
    
    action create_transport_routes {
        loop geom over: osm_geometries {
            if length(geom.points) > 1 {
                string route_type;
                int routeType_num;
                string name <- (geom.attributes["name"] as string);
                string osm_id <- (geom.attributes["osm_id"] as string);
                string busName <- "";
                string busNum <- "";
                string tramName <- "";
                string tramNum <- "";
                string subwayName <- "";
                string subwayNum <- "";

                // -------- BUS --------
                if ((geom.attributes["gama_bus_line"] != nil)
                    or (geom.attributes["route"] = "bus")
                    or (geom.attributes["highway"] = "busway")) {
                    route_type <- "bus";
                    routeType_num <- 3;
                    
                    if (geom.attributes["gama_bus_line"] != nil) {
                        busName <- geom.attributes["gama_bus_line"] as string;
                        name <- busName;
                        
                        if busName contains ":" {
                            int idx <- busName index_of ":";
                            string prefix <- copy_between(busName, 0, idx);
                            busNum <- replace(prefix, "Bus ", "");
                            
                            // Extraire la destination si elle existe
                            if idx + 1 < length(busName) {
                                string dest <- copy_between(busName, idx + 1, length(busName));
                                busName <- busName + " (" + dest + ")";
                            }
                        } else {
                            busNum <- busName;
                        }
                    } else {
                        if geom.attributes["name"] != nil {
                            busName <- geom.attributes["name"] as string;
                            name <- busName;
                        }
                        if geom.attributes["ref"] != nil {
                            busNum <- geom.attributes["ref"] as string;
                        }
                    }
                }
                // -------- TRAM --------
                else if (geom.attributes["railway"] = "tram" or geom.attributes["route"] = "tram") {
                    route_type <- "tram";
                    routeType_num <- 0;
                    if geom.attributes["name"] != nil {
                        tramName <- geom.attributes["name"] as string;
                        name <- tramName;
                    }
                    if geom.attributes["ref"] != nil {
                        tramNum <- geom.attributes["ref"] as string;
                    }
                }
                // -------- SUBWAY/MÉTRO --------
                else if (geom.attributes["railway"] = "subway" or geom.attributes["route"] = "subway") {
                    route_type <- "subway";
                    routeType_num <- 1;
                    if geom.attributes["name"] != nil {
                        subwayName <- geom.attributes["name"] as string;
                        name <- subwayName;
                    }
                    if geom.attributes["ref"] != nil {
                        subwayNum <- geom.attributes["ref"] as string;
                    }
                }
                // -------- AUTRES CHEMINS DE FER --------
                else if geom.attributes["railway"] != nil
                        and !(geom.attributes["railway"] in ["abandoned", "platform", "disused"]) {
                    route_type <- "railway";
                    routeType_num <- 2;
                    if geom.attributes["name"] != nil {
                        name <- geom.attributes["name"] as string;
                    }
                }
                // -------- CYCLEWAY --------
                else if (geom.attributes["cycleway"] != nil
                    or geom.attributes["highway"] = "cycleway") {
                    route_type <- "cycleway";
                    routeType_num <- 10;
                }
                // -------- ROAD --------
                else if geom.attributes["highway"] != nil {
                    route_type <- "road";
                    routeType_num <- 20;
                }
                else {
                    route_type <- "other";
                    routeType_num <- -1;
                }
                
                if routeType_num != -1 {
                    create network_route with: [
                        shape::geom,
                        route_type::route_type,
                        routeType_num::routeType_num,
                        name::name,
                        osm_id::osm_id,
                        busName::busName,
                        busNum::busNum,
                        tramName::tramName,
                        tramNum::tramNum,
                        subwayName::subwayName,
                        subwayNum::subwayNum
                    ];
                }
            }
        }
    }
}

species bus_stop skills: [TransportStopSkill] {
    aspect base {
        draw circle(100.0) color: #blue;
    }
    
    aspect detailed {
        draw circle(100.0) color: #blue;
        draw circle(50.0) color: #white;
    }
}

species network_route {
    geometry shape;
    string route_type;
    int routeType_num;
    string name;
    string osm_id;
    string busName;
    string busNum;
    string tramName;
    string tramNum;
    string subwayName;
    string subwayNum;
    


       aspect base {
       draw shape color: #green;
    }
    
 
}

experiment main type: gui {
 
    
    output {
        display map {
            species network_route aspect: base;
            species bus_stop aspect:  base;
            
            overlay position: {10, 10} size: {200 #px, 100 #px} background: #white transparency: 0.7 {
                draw "Réseau de transport" at: {20#px, 20#px} color: #black font: font("SansSerif", 14, #bold);
                draw string(nb_bus_routes) + " bus" at: {20#px, 40#px} color: #red font: font("SansSerif", 12, #plain);
                draw string(nb_tram_routes) + " trams" at: {20#px, 60#px} color: #blue font: font("SansSerif", 12, #plain);
                draw string(nb_subway_routes) + " métros" at: {20#px, 80#px} color: #orange font: font("SansSerif", 12, #plain);
            }
        }
        
    }
}