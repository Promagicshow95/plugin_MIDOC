/**
 * Name: reseau_transport_complet
 * Description: Réseau de transport complet comme le modèle original (sans stops)
 */

model ReseauxOSM_Nantes

global {
    // --- FICHIERS ---
    file data_file <- shape_file("../../includes/shapeFileToulouse.shp");
    geometry shape <- envelope(data_file);
    
    // --- OSM CONFIGURATION ---
    point top_left <- CRS_transform({0,0}, "EPSG:4326").location;
    point bottom_right <- CRS_transform({shape.width, shape.height}, "EPSG:4326").location;
    string adress <- "http://overpass-api.de/api/xapi_meta?*[bbox=" + top_left.x + "," + bottom_right.y + "," + bottom_right.x + "," + top_left.y + "]";
    
    // ✅ FILTRE DES ROUTES
    map<string, list> osm_data_to_generate <- [
        "highway"::[],     // TOUTES les routes (comme l'original)
        "railway"::[],     // TOUTES les voies ferrées  
        "route"::[],       // TOUTES les relations route
        "cycleway"::[]     // TOUTES les pistes cyclables
    ];
    
    // --- VARIABLES STATISTIQUES ---
    int nb_bus_routes <- 0;
    int nb_tram_routes <- 0;
    int nb_metro_routes <- 0;
    int nb_train_routes <- 0;
    int nb_cycleway_routes <- 0;
    int nb_road_routes <- 0;
    int nb_other_routes <- 0;

    init {
        write "=== CRÉATION RÉSEAU COMPLET ===";
        
        // Chargement OSM avec filtre complet
        file<geometry> osm_geometries <- osm_file<geometry>(adress, osm_data_to_generate);
        write "Géométries OSM chargées : " + length(osm_geometries);
        
        // Création des routes 
        loop geom over: osm_geometries {
            if length(geom.points) > 1 {
                do create_single_route(geom);
            }
        }
        
        // Statistiques finales
        write "\n=== RÉSEAU CRÉÉ (IDENTIQUE ORIGINAL) ===";
        write "🚌 Routes Bus : " + nb_bus_routes;
        write "🚋 Routes Tram : " + nb_tram_routes; 
        write "🚇 Routes Métro : " + nb_metro_routes;
        write "🚂 Routes Train : " + nb_train_routes;
        write "🚴 Routes Cycleway : " + nb_cycleway_routes;
        write "🛣️ Routes Road : " + nb_road_routes;
        write "❓ Autres : " + nb_other_routes;
        write "🛤️ TOTAL : " + length(network_route);
    }
    
  
    action create_single_route(geometry geom) {
        string route_type;
        int routeType_num;
        rgb route_color;
        float route_width;
        string name <- (geom.attributes["name"] as string);
		if (name = nil or name = "") {
    		name <- (geom.attributes["gama_bus_line"] as string); // juste pour afficher un nom lisible
		}

        string osm_id <- (geom.attributes["osm_id"] as string);

        // ✅ CLASSIFICATION 
        if (
    		(geom.attributes["route"] = "bus") or
    		(geom.attributes["route_master"] = "bus") or
    		(geom.attributes["route"] = "trolleybus") or
    		(geom.attributes["highway"] = "busway") or
    		(geom.attributes["bus"] != nil and geom.attributes["bus"] in ["yes", "designated"])
		) {
    		route_type <- "bus";
    		routeType_num <- 3;
    		route_color <- #blue;
    		route_width <- 2.0;
    		nb_bus_routes <- nb_bus_routes + 1;
            
        } else if (
    		geom.attributes["railway"] = "tram" or
    		geom.attributes["route"] = "tram" or
    		geom.attributes["route_master"] = "tram"
		) {
    		route_type <- "tram";
    		routeType_num <- 0;
    		route_color <- #orange;
    		route_width <- 3.0;
    		nb_tram_routes <- nb_tram_routes + 1;
            
        } else if (
            geom.attributes["railway"] = "subway" or
            geom.attributes["route"] = "subway" or
            geom.attributes["route_master"] = "subway" or
            geom.attributes["railway"] = "metro" or
            geom.attributes["route"] = "metro"
        ) {
            route_type <- "subway";
            routeType_num <- 1;
            route_color <- #red;
            route_width <- 4.0;
            nb_metro_routes <- nb_metro_routes + 1;
            
        } else if geom.attributes["railway"] != nil
        and !(geom.attributes["railway"] in ["abandoned", "platform", "disused", "construction", "proposed", "razed", "dismantled"]) {
    		route_type <- "railway";
    		routeType_num <- 2;
    		route_color <- #green;
    		route_width <- 3.5;
    		nb_train_routes <- nb_train_routes + 1;

            
        } else if (
    		geom.attributes["highway"] = "cycleway" or
    	(
        	geom.attributes["bicycle"] in ["designated", "yes"] and
        	geom.attributes["highway"] in ["path", "track", "footway"]
    	)
		) {
    		route_type <- "cycleway";
    		routeType_num <- 10;
    		route_color <- #purple;
    		route_width <- 1.5;
    		nb_cycleway_routes <- nb_cycleway_routes + 1;
            
        } else if geom.attributes["highway"] in
    		["motorway","trunk","primary","secondary","tertiary","unclassified","residential","living_street","service"] {
    		route_type <- "road";
    		routeType_num <- 20;
    		route_color <- #gray;
    		route_width <- 1.0;
    		nb_road_routes <- nb_road_routes + 1;

            
        } else {
            route_type <- "other";
            routeType_num <- -1;
            route_color <- #black;
            route_width <- 0.5;
            nb_other_routes <- nb_other_routes + 1;
        }

        // ✅ CRÉER TOUTES LES ROUTES 
        if routeType_num != -1 {
            create network_route with: [
                shape::geom,
                route_type::route_type,
                routeType_num::routeType_num,
                route_color::route_color,
                route_width::route_width,
                name::name,
                osm_id::osm_id
            ];
        }
    }
}

// CREATION DES AGENTS ROUTES
species network_route {
    geometry shape;
    string route_type;
    int routeType_num;
    rgb route_color;
    float route_width;
    string name;
    string osm_id;
    
    aspect base {
        draw shape color: route_color width: route_width;
    }
}

// EXPÉRIMENT SIMPLE
experiment main type: gui {
    output {
        display "Réseau Complet (Original)" {
            species network_route aspect: base;
            
            // Légende complète
            overlay position: {10, 10} size: {300 #px, 220 #px} background: #white transparency: 0.8 {
                draw "=== RÉSEAU COMPLET ===" at: {20#px, 20#px} color: #black font: font("Arial", 12, #bold);
                draw "🚌 Bus : " + nb_bus_routes + " routes" at: {20#px, 45#px} color: #blue;
                draw "🚋 Tram : " + nb_tram_routes + " routes" at: {20#px, 65#px} color: #orange;
                draw "🚇 Métro : " + nb_metro_routes + " routes" at: {20#px, 85#px} color: #red;
                draw "🚂 Train : " + nb_train_routes + " routes" at: {20#px, 105#px} color: #green;
                draw "🚴 Cycleway : " + nb_cycleway_routes + " routes" at: {20#px, 125#px} color: #purple;
                draw "🛣️ Roads : " + nb_road_routes + " routes" at: {20#px, 145#px} color: #gray;
                draw "❓ Autres : " + nb_other_routes + " routes" at: {20#px, 165#px} color: #black;
                draw "🛤️ TOTAL : " + length(network_route) + " routes" at: {20#px, 190#px} color: #black font: font("Arial", 10, #bold);
            }
        }
    }
}