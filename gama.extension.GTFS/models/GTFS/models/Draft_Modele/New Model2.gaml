model osm_transport_networks

global {
    string osm_file_path <- "../../includes/map.osm";
    file<geometry> osm_geometries <- osm_file(osm_file_path);
}

// Espèce générique pour une route de transport public
species network_route {
    geometry shape;
    string route_type; // "bus", "tram", "subway", "railway", "road", etc.
    string name;       // facultatif
    string osm_id;     // id OSM du segment

   
}

experiment main type: gui {
    output {
        display map {
            species network_route ;
        }
    }
    
    init {
        loop geom over: osm_geometries {
            // On ne garde que les polylignes
            if length(geom.points) > 1 {

                // --- Logique bus (même qu'OSMLoader) ---
                if (   (geom.attributes["gama_bus_line"] != nil)
                    or (geom.attributes["route"] = "bus")
                    or (geom.attributes["highway"] = "busway")) {
                    create network_route with: [
                        shape::geom,
                        route_type::"bus",
                        name::((geom.attributes["gama_bus_line"] != nil)
                                 ? geom.attributes["gama_bus_line"] as string
                                 : geom.attributes["name"] as string),
                        osm_id::(geom.attributes["osm_id"] as string)
                    ];
                }
                // --- Logique tramway ---
                else if geom.attributes["railway"] = "tram" {
                    create network_route with: [
                        shape::geom,
                        route_type::"tram",
                        name::(geom.attributes["name"] as string),
                        osm_id::(geom.attributes["osm_id"] as string)
                    ];
                }
                // --- Logique métro ---
                else if geom.attributes["railway"] = "subway" {
                    create network_route with: [
                        shape::geom,
                        route_type::"subway",
                        name::(geom.attributes["name"] as string),
                        osm_id::(geom.attributes["osm_id"] as string)
                    ];
                }
                // --- Logique railway générique (hors rails désactivés) ---
                else if geom.attributes["railway"] != nil
                      and !(geom.attributes["railway"] in ["abandoned", "platform", "disused"]) {
                    create network_route with: [
                        shape::geom,
                        route_type::"railway",
                        name::(geom.attributes["name"] as string),
                        osm_id::(geom.attributes["osm_id"] as string)
                    ];
                }
                // --- Logique cycleway ---
                else if geom.attributes["cycleway"] != nil
                      or geom.attributes["highway"] = "cycleway" {
                    create network_route with: [
                        shape::geom,
                        route_type::"cycleway",
                        name::(geom.attributes["name"] as string),
                        osm_id::(geom.attributes["osm_id"] as string)
                    ];
                }
                // --- Logique routes classiques ---
                else if geom.attributes["highway"] != nil {
                    create network_route with: [
                        shape::geom,
                        route_type::"road",
                        name::(geom.attributes["name"] as string),
                        osm_id::(geom.attributes["osm_id"] as string)
                    ];
                }
            }
        }
    }
}
