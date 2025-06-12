model osm_transport_networks

global {
   point top_left <- CRS_transform({0,0}, "EPSG:4326").location;
   point bottom_right <- CRS_transform({shape.width, shape.height}, "EPSG:4326").location;
   string adress <-"http://overpass-api.de/api/xapi_meta?*[bbox="+top_left.x+"," + bottom_right.y + ","+ bottom_right.x + "," + top_left.y+"]";
			
   file<geometry> osm_geometries <- osm_file<geometry> (adress, osm_data_to_generate);
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
    
    init{
    	   
        // Create bus_stop agents from the GTFS data
       create bus_stop from: gtfs_f  {
       	
				
       }
    }
    
   
}


species bus_stop skills: [TransportStopSkill] {
	
 
     aspect base {
     	
     	
		draw circle (100.0) at: location color:#blue;	
     }
}
// Espèce générique pour une route de transport public
species network_route {
    geometry shape;
    string route_type; // "bus", "tram", ...
    int routeType_num; // 0, 1, 2, 3...
    string name;
    string osm_id;
    
     aspect base {
       draw shape color: #green;
    }

   
}

experiment main type: gui {
    output {
        display map {
            species network_route aspect:base ;
            species bus_stop aspect: base;
        }
    }
    
    init {
    loop geom over: osm_geometries {
        if length(geom.points) > 1 {
            string route_type;
            int routeType_num;
            string name <- (geom.attributes["name"] as string);
            string osm_id <- (geom.attributes["osm_id"] as string);

            // Bus
            if ((geom.attributes["gama_bus_line"] != nil)
                or (geom.attributes["route"] = "bus")
                or (geom.attributes["highway"] = "busway")) {
                route_type <- "bus";
                routeType_num <- 3;
                if (geom.attributes["gama_bus_line"] != nil) {
                    name <- geom.attributes["gama_bus_line"] as string;
                }
            }
            // Tram
            else if geom.attributes["railway"] = "tram" {
                route_type <- "tram";
                routeType_num <- 0;
            }
            // Subway
            else if geom.attributes["railway"] = "subway" {
                route_type <- "subway";
                routeType_num <- 1;
            }
            // Railway générique
            else if geom.attributes["railway"] != nil
                    and !(geom.attributes["railway"] in ["abandoned", "platform", "disused"]) {
                route_type <- "railway";
                routeType_num <- 2;
            }
            // Cycleway
            else if (geom.attributes["cycleway"] != nil
                or geom.attributes["highway"] = "cycleway") {
                route_type <- "cycleway";
                routeType_num <- 10; // code perso (non GTFS)
            }
            // Road classique
            else if geom.attributes["highway"] != nil {
                route_type <- "road";
                routeType_num <- 20; // code perso (non GTFS)
            }
            else {
                route_type <- "other";
                routeType_num <- -1;
            }
            
            // Crée l’agent seulement si le type est reconnu
            if routeType_num != -1 {
                create network_route with: [
                    shape::geom,
                    route_type::route_type,
                    routeType_num::routeType_num,
                    name::name,
                    osm_id::osm_id
                ];
            }
        }
    }
}

}


