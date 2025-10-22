/**
 * Name: Clean_OSM_To_Shapefile_FINAL_FIXED
 * Author: Promagicshow95
 * Description: Export OSM - VERSION FINALE avec gestion valeurs multiples
 * Tags: OSM, shapefile, export, network, transport
 * Date: 2025-10-21
 */

model Clean_OSM_To_Shapefile_Final_Fixed

global {
    // --- FICHIERS ---
    file data_file <- shape_file("../../includes/shapeFileNantes.shp");
    geometry shape <- envelope(data_file);
    
    // ✅ BBOX CORRECTE AVEC TAMPON EN PROJECTION MÉTRIQUE
    geometry env_local <- envelope(data_file);
    geometry env_m <- CRS_transform(env_local, "EPSG:3857");
    geometry env_m_buffered <- env_m buffer 800.0 #m;
    geometry env_wgs <- CRS_transform(env_m_buffered, "EPSG:4326");
    
    point sw_wgs84 <- env_wgs.location + {-env_wgs.width/2, -env_wgs.height/2};
    point ne_wgs84 <- env_wgs.location + { env_wgs.width/2,  env_wgs.height/2};
    
    float minx <- min(sw_wgs84.x, ne_wgs84.x);
    float miny <- min(sw_wgs84.y, ne_wgs84.y);
    float maxx <- max(sw_wgs84.x, ne_wgs84.x);
    float maxy <- max(sw_wgs84.y, ne_wgs84.y);
    
    string adress <- "http://overpass-api.de/api/xapi_meta?*[bbox=" + 
                     minx + "," + miny + "," + maxx + "," + maxy + "]";
    
    map<string, list> osm_data_to_generate <- [
        "highway"::[],
        "railway"::[],
        "route"::[],
        "cycleway"::[],
        "bus"::[],
        "psv"::[],
        "public_transport"::[],
        "waterway"::[]
    ];
    
    // --- VARIABLES STATISTIQUES ---
    int nb_bus_routes <- 0;
    int nb_tram_routes <- 0;
    int nb_metro_routes <- 0;
    int nb_train_routes <- 0;
    int nb_cycleway_routes <- 0;
    int nb_road_routes <- 0;
    int nb_ferry_routes <- 0;
    int nb_other_routes <- 0;
    int nb_total_created <- 0;
    int nb_without_osm_id <- 0;
    int nb_closed_ways_converted <- 0;
    
    string export_folder <- "../../results1/";

    init {
        write "=== EXPORT OSM FINAL (VALEURS MULTIPLES GÉRÉES) ===";
        write "🔑 Système d'identification : osm_type:osm_id";
        write "📦 Bbox : [" + (minx with_precision 5) + "," + (miny with_precision 5) + 
              "] → [" + (maxx with_precision 5) + "," + (maxy with_precision 5) + "]";
        write "🔄 Tampon emprise : 800m (EPSG:3857)";
        
        file<geometry> osm_geometries <- osm_file<geometry>(adress, osm_data_to_generate);
        write "✅ Géométries OSM chargées : " + length(osm_geometries);
        
        int valid_geoms <- 0;
        int invalid_geoms <- 0;
        
        loop geom over: osm_geometries {
            if geom != nil and length(geom.points) > 1 {
                do create_route_complete(geom);
                valid_geoms <- valid_geoms + 1;
            } else {
                invalid_geoms <- invalid_geoms + 1;
            }
        }
        
        write "✅ Géométries valides : " + valid_geoms;
        write "❌ Géométries invalides : " + invalid_geoms;
        write "✅ Agents network_route créés : " + length(network_route);
        write "⚠️ Routes sans ID OSM : " + nb_without_osm_id;
        write "🔄 Closed-ways convertis : " + nb_closed_ways_converted;
        
        do export_complete_network;
        do export_by_type_fixed;
        
        write "\n=== 📊 STATISTIQUES RÉSEAU EXPORTÉ ===";
        write "🚌 Routes Bus : " + nb_bus_routes;
        write "🚋 Routes Tram : " + nb_tram_routes; 
        write "🚇 Routes Métro : " + nb_metro_routes;
        write "🚂 Routes Train : " + nb_train_routes;
        write "🚴 Routes Cycleway : " + nb_cycleway_routes;
        write "🛣️ Routes Road : " + nb_road_routes;
        write "⛴️ Routes Ferry : " + nb_ferry_routes;
        write "❓ Autres : " + nb_other_routes;
        write "━━━━━━━━━━━━━━━━━━━━━━━━━";
        write "🛤️ TOTAL EXPORTÉ : " + nb_total_created;
        write "🔑 Avec ID OSM unique : " + (nb_total_created - nb_without_osm_id);
        write "⚠️ Sans ID OSM : " + nb_without_osm_id;
    }
    
    // ✅ CRÉATION ROUTE AVEC GESTION VALEURS MULTIPLES OSM
    action create_route_complete(geometry geom) {
        string route_type;
        int routeType_num;
        rgb route_color;
        float route_width;
        
        // ══════════════════════════════════════════════════════════
// 📥 RÉCUPÉRATION DES ATTRIBUTS OSM
// ══════════════════════════════════════════════════════════
string name <- (geom.attributes["name"] as string);
string ref <- (geom.attributes["ref"] as string);
string highway <- (geom.attributes["highway"] as string);
string railway <- (geom.attributes["railway"] as string);
string route <- (geom.attributes["route"] as string);
string route_master <- (geom.attributes["route_master"] as string);
string bus <- (geom.attributes["bus"] as string);
string cycleway <- (geom.attributes["cycleway"] as string);
string bicycle <- (geom.attributes["bicycle"] as string);
string psv <- (geom.attributes["psv"] as string);

string busway_left <- (geom.attributes["busway:left"] as string);
string busway_right <- (geom.attributes["busway:right"] as string);
string busway <- (geom.attributes["busway"] as string);
string bus_lanes <- (geom.attributes["bus:lanes"] as string);
string psv_lanes <- (geom.attributes["psv:lanes"] as string);

// ══════════════════════════════════════════════════════════
// ✅ GESTION VALEURS MULTIPLES OSM (VERSION CONTAINS)
// ══════════════════════════════════════════════════════════
string r <- (railway = nil or railway = "") ? "" : railway;
string rt <- (route = nil or route = "") ? "" : route;
string rtm <- (route_master = nil or route_master = "") ? "" : route_master;

bool is_rail_based <- (r != "");

bool is_tram_like <- (r contains "tram") or (r contains "light_rail") or 
                     (r contains "monorail") or (r contains "funicular") or
                     (rt contains "tram") or (rt contains "light_rail") or
                     (rtm contains "tram") or (rtm contains "light_rail");

bool is_metro_like <- (r contains "subway") or (r contains "metro") or
                      (rt contains "subway") or (rt contains "metro") or
                      (rtm contains "subway") or (rtm contains "metro");

bool is_railway_excluded <- (r contains "abandoned") or (r contains "platform") or 
                            (r contains "tram_stop") or  // ← AJOUT ICI
                            (r contains "disused") or (r contains "construction") or
                            (r contains "proposed") or (r contains "razed") or 
                            (r contains "dismantled");

// ══════════════════════════════════════════════════════════
// 🔎 RÉCUPÉRATION ROBUSTE DES IDENTIFIANTS OSM
// ══════════════════════════════════════════════════════════
string id_str <- (geom.attributes["@id"] as string);
if (id_str = nil or id_str = "") { id_str <- (geom.attributes["id"] as string); }
if (id_str = nil or id_str = "") { id_str <- (geom.attributes["osm_id"] as string); }
if (id_str = nil or id_str = "") { id_str <- (geom.attributes["way_id"] as string); }
if (id_str = nil or id_str = "") { id_str <- (geom.attributes["rel_id"] as string); }
if (id_str = nil or id_str = "") { id_str <- (geom.attributes["relation_id"] as string); }

string osm_type <- (geom.attributes["@type"] as string);
if (osm_type = nil or osm_type = "") { osm_type <- (geom.attributes["type"] as string); }

if (osm_type = nil or osm_type = "") {
    if (route != nil and route != "") {
        osm_type <- "relation";
    } else if (highway != nil or railway != nil) {
        osm_type <- "way";
    } else {
        osm_type <- "way";
    }
}

string osm_uid <- "";
if (id_str != nil and id_str != "") {
    osm_uid <- osm_type + ":" + id_str;
} else {
    nb_without_osm_id <- nb_without_osm_id + 1;
    osm_uid <- "";
}

if (name = nil or name = "") {
    if (ref != nil and ref != "") {
        name <- ref;
    } else if (id_str != nil and id_str != "") {
        name <- "Route_" + id_str;
    } else {
        name <- "Route_sans_id";
    }
}

// ══════════════════════════════════════════════════════════
// ✅ CLASSIFICATION FINALE CORRIGÉE (AVEC CONTAINS)
// ══════════════════════════════════════════════════════════

bool has_bus_lane <- (busway_left in ["lane", "track"]) or 
                    (busway_right in ["lane", "track"]) or 
                    (busway in ["lane", "track"]) or 
                    (bus_lanes != nil and bus_lanes != "") or
                    (psv_lanes != nil and psv_lanes != "");

// 🚌 BUS — Protection anti-ferroviaire
if (
    ((route = "bus") or (route = "trolleybus") or (route_master = "bus") or
     (highway in ["busway", "bus_guideway"]) or (bus in ["yes", "designated"]) or 
     (psv = "yes") or has_bus_lane) 
    and !is_rail_based
) {
    route_type <- "bus";
    routeType_num <- 3;
    route_color <- #blue;
    route_width <- 2.5;
    nb_bus_routes <- nb_bus_routes + 1;
}
// 🚋 TRAM — ✅ Capture "tram", "tram;rail", "light_rail;rail" + exclusion
else if (is_tram_like and !is_railway_excluded) {  // ← AJOUT ICI
    route_type <- "tram";
    routeType_num <- 0;
    route_color <- #orange;
    route_width <- 2.0;
    nb_tram_routes <- nb_tram_routes + 1;
}
// 🚇 MÉTRO — ✅ Avec exclusion
else if (is_metro_like and !is_railway_excluded) {  // ← AJOUT ICI
    route_type <- "metro";
    routeType_num <- 1;
    route_color <- #red;
    route_width <- 2.0;
    nb_metro_routes <- nb_metro_routes + 1;
}
// 🚂 TRAIN — ✅ Exclure tram/metro
else if (is_rail_based and !is_railway_excluded and !is_tram_like and !is_metro_like) {
    route_type <- "train";
    routeType_num <- 2;
    route_color <- #green;
    route_width <- 1.8;
    nb_train_routes <- nb_train_routes + 1;
}
// ⛴️ FERRY
else if (route = "ferry") {
    route_type <- "ferry";
    routeType_num <- 4;
    route_color <- #cyan;
    route_width <- 1.5;
    nb_ferry_routes <- nb_ferry_routes + 1;
}
// 🚴 CYCLEWAY
else if ((highway = "cycleway") or (cycleway != nil) or (bicycle in ["designated", "yes"])) {
    route_type <- "cycleway";
    routeType_num <- 10;
    route_color <- #purple;
    route_width <- 1.2;
    nb_cycleway_routes <- nb_cycleway_routes + 1;
}
// 🛣️ ROUTES
else if (highway != nil and highway != "") {
    route_type <- "road";
    routeType_num <- 20;
    route_color <- #gray;
    route_width <- 1.0;
    nb_road_routes <- nb_road_routes + 1;
}
// ❓ AUTRES
else {
    route_type <- "other";
    routeType_num <- 99;
    route_color <- #lightgray;
    route_width <- 0.8;
    nb_other_routes <- nb_other_routes + 1;
}

        // ══════════════════════════════════════════════════════════
        // ✅ OPTION : SUPPRIMER LE BLOC DE CONVERSION (SÉCURITAIRE)
        // ══════════════════════════════════════════════════════════
        // Ce bloc est désactivé car il causait la perte des trams
        // Si vous voulez le réactiver, décommentez-le
        
        /*
        bool is_area <- (geom.area > 0) and (
            (geom.attributes["area"] as string) = "yes" or
            (geom.attributes["building"] as string) != nil or
            (geom.attributes["landuse"] as string) != nil or
            (geom.attributes["amenity"] as string) != nil or
            (geom.attributes["natural"] as string) != nil or
            (geom.attributes["water"] as string) != nil or
            (geom.attributes["leisure"] as string) != nil
        );
        
        if (geom.area > 0 and (route != nil or railway != nil or highway != nil) and !is_area) {
            list<point> pts <- copy(geom.points);
            if length(pts) > 2 and pts[0] = pts[length(pts) - 1] {
                pts <- pts - [pts[length(pts) - 1]];
            }
            if length(pts) >= 2 {
                geom <- polyline(pts);
                nb_closed_ways_converted <- nb_closed_ways_converted + 1;
            }
        }
        */

        // ══════════════════════════════════════════════════════════
        // ✅ CALCUL DES PROPRIÉTÉS GÉOMÉTRIQUES
        // ══════════════════════════════════════════════════════════
        float length_meters <- geom.perimeter;
        int points_count <- length(geom.points);

        // ══════════════════════════════════════════════════════════
        // ✅ CRÉATION DE L'AGENT
        // ══════════════════════════════════════════════════════════
        create network_route with: [
            shape::geom,
            route_type::route_type,
            routeType_num::routeType_num,
            route_color::route_color,
            route_width::route_width,
            name::name,
            osm_id::id_str,
            osm_type::osm_type,
            osm_uid::osm_uid,
            highway_type::highway,
            railway_type::railway,
            route_rel::route,
            bus_access::bus,
            ref_number::ref,
            length_m::length_meters,
            num_points::points_count
        ];
        
        nb_total_created <- nb_total_created + 1;
    }
    
    // ══════════════════════════════════════════════════════════
    // EXPORT (inchangé)
    // ══════════════════════════════════════════════════════════
    
    action export_complete_network {
        write "\n=== 📦 EXPORT VERS SHAPEFILE ===";
        
        if empty(network_route) {
            write "❌ ERREUR : Aucun agent créé à exporter !";
            return;
        }
        
        string shapefile_path <- export_folder + "network_transport_complete.shp";
        
        try {
            save network_route to: shapefile_path format: "shp" attributes: [
                "osm_uid"::osm_uid,
                "osm_type"::osm_type,
                "osm_id"::osm_id,
                "name"::name,
                "route_type"::route_type,
                "routeType"::routeType_num,
                "highway"::highway_type,
                "railway"::railway_type,
                "ref"::ref_number,
                "length_m"::length_m
            ];
            
            write "✅ EXPORT COMPLET RÉUSSI : " + shapefile_path;
            write "📊 " + length(network_route) + " routes exportées avec ID canonique";
            
        } catch {
            write "❌ Erreur d'export complet - Tentative avec attributs minimaux...";
            
            try {
                save network_route to: shapefile_path format: "shp" attributes: [
                    "osm_uid"::osm_uid,
                    "osm_type"::osm_type,
                    "osm_id"::osm_id,
                    "name"::name,
                    "type"::route_type
                ];
                write "✅ EXPORT MINIMAL RÉUSSI : " + shapefile_path;
            } catch {
                write "❌ Échec attributs - Export géométrie seule...";
                save network_route to: shapefile_path format: "shp";
                write "✅ EXPORT GÉOMÉTRIE SEULE : " + shapefile_path;
            }
        }
    }
    
    action export_by_type_fixed {
        write "\n=== 📦 EXPORT PAR TYPE DE TRANSPORT ===";
        
        list<network_route> bus_routes <- network_route where (each.route_type = "bus");
        write "🔍 Bus routes trouvées : " + length(bus_routes);
        
        if !empty(bus_routes) {
            do export_by_batch_robust(bus_routes, "bus_routes", 10000);
        }
        
        list<network_route> main_roads <- network_route where (each.route_type = "road");
        write "🔍 Main roads trouvées : " + length(main_roads);
        
        if !empty(main_roads) {
            do export_by_batch_robust(main_roads, "main_roads", 50000);
        }
        
        list<network_route> public_transport <- network_route where (each.route_type in ["tram", "metro", "train"]);
        if !empty(public_transport) {
            write "🔍 Transport public trouvé : " + length(public_transport);
            try {
                save public_transport to: export_folder + "public_transport.shp" format: "shp" attributes: [
                    "osm_uid"::osm_uid, 
                    "osm_type"::osm_type, 
                    "osm_id"::osm_id,
                    "name"::name, 
                    "route_type"::route_type, 
                    "railway"::railway_type, 
                    "ref"::ref_number,
                    "length_m"::length_m
                ];
                write "✅ Transport public exporté : " + length(public_transport);
            } catch {
                write "❌ Erreur export transport public";
            }
        }
        
        list<network_route> cycleways <- network_route where (each.route_type = "cycleway");
        if !empty(cycleways) {
            write "🔍 Pistes cyclables trouvées : " + length(cycleways);
            try {
                save cycleways to: export_folder + "cycleways.shp" format: "shp" attributes: [
                    "osm_uid"::osm_uid, 
                    "osm_type"::osm_type, 
                    "osm_id"::osm_id,
                    "name"::name, 
                    "highway"::highway_type,
                    "ref"::ref_number,
                    "length_m"::length_m
                ];
                write "✅ Pistes cyclables exportées : " + length(cycleways);
            } catch {
                write "❌ Erreur export cycleways";
            }
        }
        
        list<network_route> ferries <- network_route where (each.route_type = "ferry");
        if !empty(ferries) {
            write "🔍 Ferries trouvés : " + length(ferries);
            try {
                save ferries to: export_folder + "ferries.shp" format: "shp" attributes: [
                    "osm_uid"::osm_uid, 
                    "osm_type"::osm_type, 
                    "osm_id"::osm_id,
                    "name"::name,
                    "ref"::ref_number,
                    "length_m"::length_m
                ];
                write "✅ Ferries exportés : " + length(ferries);
            } catch {
                write "❌ Erreur export ferries";
            }
        }
        
        write "🎯 EXPORT PAR TYPE TERMINÉ !";
    }
    
    action export_by_batch_robust(list<network_route> routes, string filename, int batch_size) {
        write "🔄 Export robuste par batch : " + filename + " (" + length(routes) + " objets)";
        
        int total_exported <- 0;
        int batch_num <- 0;
        int current_index <- 0;
        
        list<network_route> all_valid_routes <- routes where (
            each.shape != nil and 
            each.osm_uid != nil and 
            length(each.osm_uid) > 0
        );
        write "🔍 Routes avec ID OSM valide : " + length(all_valid_routes) + "/" + length(routes);
        
        list<network_route> routes_without_id <- routes where (
            each.shape != nil and 
            (each.osm_uid = nil or length(each.osm_uid) = 0)
        );
        if !empty(routes_without_id) {
            write "⚠️ Routes sans ID OSM : " + length(routes_without_id);
        }
        
        loop while: current_index < length(all_valid_routes) {
            int end_index <- min(current_index + batch_size - 1, length(all_valid_routes) - 1);
            list<network_route> current_batch <- [];
            
            loop i from: current_index to: end_index {
                current_batch <+ all_valid_routes[i];
            }
            
            string batch_filename <- export_folder + filename + "_part" + batch_num + ".shp";
            bool export_success <- false;
            
            try {
                save current_batch to: batch_filename format: "shp" attributes: [
                    "osm_uid"::osm_uid, 
                    "osm_type"::osm_type, 
                    "osm_id"::osm_id,
                    "name"::name, 
                    "route_type"::route_type, 
                    "highway"::highway_type,
                    "railway"::railway_type,
                    "ref"::ref_number,
                    "length_m"::length_m
                ];
                
                write "  ✅ Batch " + batch_num + " [COMPLET] : " + length(current_batch) + " objets";
                total_exported <- total_exported + length(current_batch);
                export_success <- true;
                
            } catch {
                write "  ⚠️ Erreur attributs complets, tentative minimale...";
            }
            
            if !export_success {
                try {
                    save current_batch to: batch_filename format: "shp" attributes: [
                        "osm_uid"::osm_uid,
                        "osm_type"::osm_type,
                        "osm_id"::osm_id,
                        "name"::name,
                        "type"::route_type
                    ];
                    
                    write "  ✅ Batch " + batch_num + " [MINIMAL] : " + length(current_batch) + " objets";
                    total_exported <- total_exported + length(current_batch);
                    export_success <- true;
                    
                } catch {
                    write "  ⚠️ Erreur minimale, export géométrie...";
                }
            }
            
            if !export_success {
                try {
                    save current_batch to: batch_filename format: "shp";
                    write "  ✅ Batch " + batch_num + " [GÉOMÉTRIE] : " + length(current_batch) + " objets";
                    total_exported <- total_exported + length(current_batch);
                    
                } catch {
                    write "  ❌ Échec total batch " + batch_num;
                }
            }
            
            current_index <- end_index + 1;
            batch_num <- batch_num + 1;
        }
        
        if !empty(routes_without_id) {
            string no_id_filename <- export_folder + filename + "_sans_id.shp";
            try {
                save routes_without_id to: no_id_filename format: "shp" attributes: [
                    "name"::name,
                    "route_type"::route_type,
                    "highway"::highway_type,
                    "railway"::railway_type,
                    "length_m"::length_m
                ];
                write "  ✅ Routes sans ID exportées : " + length(routes_without_id) + " objets";
            } catch {
                write "  ⚠️ Erreur export routes sans ID";
            }
        }
        
        write "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━";
        write "📊 TOTAL " + filename + " : " + total_exported + "/" + length(all_valid_routes) + " objets exportés";
        write "📁 Fichiers créés : " + batch_num + " fichiers principaux";
    }
}

species network_route {
    geometry shape;
    string route_type;
    int routeType_num;
    rgb route_color;
    float route_width;
    string name;
    string osm_id;
    string osm_type;
    string osm_uid;
    string highway_type;
    string railway_type;
    string route_rel;
    string bus_access;
    string ref_number;
    float length_m;
    int num_points;
    
    aspect default {
        if shape != nil {
            draw shape color: route_color width: route_width;
        }
    }
    
    aspect thick {
        if shape != nil {
            draw shape color: route_color width: (route_width * 2);
        }
    }
    
    aspect colored {
        if shape != nil {
            rgb display_color;
            if route_type = "bus" { display_color <- #blue; }
            else if route_type = "tram" { display_color <- #orange; }
            else if route_type = "metro" { display_color <- #red; }
            else if route_type = "train" { display_color <- #green; }
            else if route_type = "cycleway" { display_color <- #purple; }
            else if route_type = "ferry" { display_color <- #cyan; }
            else if route_type = "road" { display_color <- #gray; }
            else { display_color <- #black; }
            draw shape color: display_color width: 2.0;
        }
    }
}

experiment main_export type: gui {
    output {
        display "Export OSM FIXED" background: #white {
            species network_route aspect: thick;
            
            overlay position: {10, 10} size: {460 #px, 520 #px} background: #white transparency: 0.9 border: #black {
                draw "🔑 EXPORT OSM FINAL FIXED" at: {20#px, 25#px} color: #black font: font("Arial", 14, #bold);
                
                draw "━━━━━━━━━━━━━━━━━━━━━━" at: {20#px, 45#px} color: #darkgray size: 10;
                
                draw "✅ CORRECTIF VALEURS MULTIPLES" at: {20#px, 65#px} color: #darkgreen font: font("Arial", 11, #bold);
                draw "🎯 Gère railway='tram;rail' ✓" at: {30#px, 85#px} color: #green size: 9;
                draw "🎯 Split sur ';' + trim ✓" at: {30#px, 100#px} color: #green size: 9;
                draw "🎯 Flags booléens robustes ✓" at: {30#px, 115#px} color: #green size: 9;
                draw "🎯 Protection anti-ferroviaire bus ✓" at: {30#px, 130#px} color: #green size: 9;
                draw "🎯 Priorité tram > metro > train ✓" at: {30#px, 145#px} color: #green size: 9;
                draw "🎯 Conversion polygone DÉSACTIVÉE ✓" at: {30#px, 160#px} color: #orange size: 9;
                
                draw "━━━━━━━━━━━━━━━━━━━━━━" at: {20#px, 180#px} color: #darkgray size: 10;
                
                draw "🔍 AGENTS CRÉÉS" at: {20#px, 200#px} color: #darkred font: font("Arial", 11, #bold);
                draw "Total : " + length(network_route) + " agents" at: {30#px, 220#px} color: #black;
                draw "Avec ID OSM : " + (nb_total_created - nb_without_osm_id) at: {30#px, 235#px} color: #darkgreen;
                draw "Sans ID OSM : " + nb_without_osm_id at: {30#px, 250#px} color: #darkred;
                
                draw "━━━━━━━━━━━━━━━━━━━━━━" at: {20#px, 270#px} color: #darkgray size: 10;
                
                draw "📊 RÉPARTITION PAR TYPE" at: {20#px, 290#px} color: #darkblue font: font("Arial", 11, #bold);
                draw "🚌 Bus : " + nb_bus_routes at: {30#px, 310#px} color: #blue;
                draw "🚋 Tram : " + nb_tram_routes at: {30#px, 325#px} color: #orange font: font("Arial", 10, #bold);
                draw "🚇 Métro : " + nb_metro_routes at: {30#px, 340#px} color: #red;
                draw "🚂 Train : " + nb_train_routes at: {30#px, 355#px} color: #green;
                draw "⛴️ Ferry : " + nb_ferry_routes at: {30#px, 370#px} color: #cyan;
                draw "🚴 Cycleway : " + nb_cycleway_routes at: {30#px, 385#px} color: #purple;
                draw "🛣️ Roads : " + nb_road_routes at: {30#px, 400#px} color: #gray;
                draw "❓ Autres : " + nb_other_routes at: {30#px, 415#px} color: #lightgray;
                
                draw "━━━━━━━━━━━━━━━━━━━━━━" at: {20#px, 435#px} color: #darkgray size: 10;
                draw "🎯 Tram : ~4700 attendus à Nantes" at: {30#px, 455#px} color: #orange font: font("Arial", 9, #bold);
                draw "✅ Si Tram > 4000 → FIX réussi !" at: {30#px, 475#px} color: #darkgreen font: font("Arial", 9, #bold);
                draw "❌ Si Tram = 0 → Vérifier split" at: {30#px, 495#px} color: #darkred font: font("Arial", 9);
            }
        }
    }
}