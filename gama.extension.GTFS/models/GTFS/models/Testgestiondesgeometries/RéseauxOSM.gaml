/**
* Name: visualiser_network_route
* Description: Visualiser les network_route OSM importées via shapefile ou osm_file
*/

model visualiser_network_route

global {
    // --- FICHIERS ---
    file data_file <- shape_file("../../includes/shapeFileNantes.shp"); // à adapter selon la ville
    geometry shape <- envelope(data_file);

    // --- OSM ---
    point top_left <- CRS_transform({0,0}, "EPSG:4326").location;
    point bottom_right <- CRS_transform({shape.width, shape.height}, "EPSG:4326").location;
    string adress <- "http://overpass-api.de/api/xapi_meta?*[bbox=" + top_left.x + "," + bottom_right.y + "," + bottom_right.x + "," + top_left.y + "]";
    file<geometry> osm_geometries <- osm_file<geometry>(adress, osm_data_to_generate);
    // file<geometry> osm_geometries <- osm_file("../../includes/Nantes_map (2).osm", osm_data_to_generate);

    // --- FILTRES OSM ---
    map<string, list> osm_data_to_generate <- [
        "highway"::[],
        "railway"::[],
        "route"::[],
        "cycleway"::[]
    ];

    init {
        write "Création des network_route depuis OSM...";
        loop geom over: osm_geometries {
            if length(geom.points) > 1 {
                do create_single_route(geom);
            }
        }
        write "Routes créées : " + length(network_route);
    }

    action create_single_route(geometry geom) {
        string route_type;
        int routeType_num;
        string name <- (geom.attributes["name"] as string);
        string osm_id <- (geom.attributes["osm_id"] as string);

        if ((geom.attributes["gama_bus_line"] != nil)
            or (geom.attributes["route"] = "bus")
            or (geom.attributes["highway"] = "busway")) {
            route_type <- "bus";
            routeType_num <- 3;
        } else if geom.attributes["railway"] = "tram" {
            route_type <- "tram";
            routeType_num <- 0;
        } else if (
            geom.attributes["railway"] = "subway" or
            geom.attributes["route"] = "subway" or
            geom.attributes["route_master"] = "subway" or
            geom.attributes["railway"] = "metro" or
            geom.attributes["route"] = "metro"
        ) {
            route_type <- "subway";
            routeType_num <- 1;
        } else if geom.attributes["railway"] != nil
                and !(geom.attributes["railway"] in ["abandoned", "platform", "disused"]) {
            route_type <- "railway";
            routeType_num <- 2;
        } else if (geom.attributes["cycleway"] != nil
                or geom.attributes["highway"] = "cycleway") {
            route_type <- "cycleway";
            routeType_num <- 10;
        } else if geom.attributes["highway"] != nil {
            route_type <- "road";
            routeType_num <- 20;
        } else {
            route_type <- "other";
            routeType_num <- -1;
        }

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

species network_route {
    geometry shape;
    string route_type;
    int routeType_num;
    string name;
    string osm_id;

    aspect base {
        draw shape color: #green;
    }
}

experiment main type: gui {
    output {
        display map {
            species network_route aspect: base;
        }
    }
}
