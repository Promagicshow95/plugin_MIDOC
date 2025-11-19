/**
 * Visualisation GTFS + OSM + Arrêts (3 modes)
 * 
 * 3 EXPÉRIENCES:
 * 1. Tout : OSM + GTFS + Stops
 * 2. GTFS uniquement : GTFS + Stops
 * 3. OSM uniquement : OSM + Stops
 */

model VisualizeGTFS_OSM_ThreeModes

global {
    // ============================================================
    // === FICHIERS ===
    // ============================================================
    gtfs_file gtfs_f <- gtfs_file("../../includes/nantes_gtfs");
    shape_file boundary_shp <- shape_file("../../includes/ShapeFileNantes.shp");
    string osm_folder <- "../../results1/";
    
    geometry shape <- envelope(boundary_shp);
    
    // ============================================================
    // === STATISTIQUES ===
    // ============================================================
    int nb_gtfs_shapes <- 0;
    int nb_osm_routes <- 0;
    int nb_bus_stops <- 0;
    
    // ============================================================
    // === INITIALISATION ===
    // ============================================================
    init {
        write "╔═══════════════════════════════════════════════════════╗";
        write "║   VISUALISATION GTFS + OSM + ARRÊTS (3 MODES)       ║";
        write "╚═══════════════════════════════════════════════════════╝\n";
        
        // ÉTAPE 1: Charger arrêts de bus GTFS
        write "🚏 Chargement arrêts de bus...";
        create bus_stop from: gtfs_f;
        nb_bus_stops <- length(bus_stop where (each.routeType = 3));
        write "  ✅ " + nb_bus_stops + " arrêts de bus";
        
        // ÉTAPE 2: Charger shapes GTFS
        write "\n📍 Chargement shapes GTFS...";
        create gtfs_shape from: gtfs_f;
        
        // Filtrer seulement les bus
        list bus_shape_ids <- [];
        ask (bus_stop where (each.routeType = 3 and each.tripShapeMap != nil)) {
            loop sid over: values(tripShapeMap) {
                if (sid != nil and !(bus_shape_ids contains sid)) {
                    bus_shape_ids <- bus_shape_ids + sid;
                }
            }
        }
        
        ask gtfs_shape {
            is_bus <- bus_shape_ids contains shapeId;
        }
        
        nb_gtfs_shapes <- length(gtfs_shape where each.is_bus);
        write "  ✅ " + nb_gtfs_shapes + " shapes GTFS (bus)";
        
        // ÉTAPE 3: Charger routes OSM
        write "\n🗺️  Chargement routes OSM...";
        int i <- 0;
        bool continue_loading <- true;
        
        loop while: continue_loading {
            string filepath <- osm_folder + "bus_routes_part" + i + ".shp";
            try {
                shape_file shp <- shape_file(filepath);
                create osm_route from: shp;
                i <- i + 1;
            } catch {
                continue_loading <- false;
            }
        }
        
        nb_osm_routes <- length(osm_route);
        write "  ✅ " + nb_osm_routes + " routes OSM";
        
        // Résumé
        write "\n╔═══════════════════════════════════════════════════════╗";
        write "║ Arrêts de bus: " + nb_bus_stops + " (ROUGE)";
        write "║ Shapes GTFS:   " + nb_gtfs_shapes + " (BLEU)";
        write "║ Routes OSM:    " + nb_osm_routes + " (VERT)";
        write "╚═══════════════════════════════════════════════════════╝";
        write "\n✅ Visualisation prête ! Choisissez une expérience.";
        write "\n📋 3 MODES DISPONIBLES:";
        write "   1. Exp_All        → OSM + GTFS + Stops";
        write "   2. Exp_GTFS_Only  → GTFS + Stops (sans OSM)";
        write "   3. Exp_OSM_Only   → OSM + Stops (sans GTFS)";
    }
}

// ============================================================
// === ESPÈCES ===
// ============================================================

// Arrêts GTFS - ROUGE (cercles)
species bus_stop skills: [TransportStopSkill] {
    aspect base {
        // Seulement les arrêts de bus (routeType = 3)
        if (routeType = 3) {
            draw circle(50) color: #red border: #darkred;
        }
    }
}

// Shapes GTFS - BLEU (lignes)
species gtfs_shape skills: [TransportShapeSkill] {
    bool is_bus <- false;
    
    aspect default {
        if (is_bus and shape != nil) {
            draw shape color: #blue width: 2;
        }
    }
}

// Routes OSM - VERT (lignes)
species osm_route {
    aspect default {
        if (shape != nil) {
            draw shape color: #green width: 2;
        }
    }
}

// ============================================================
// === EXPÉRIENCE 1: TOUT (OSM + GTFS + Stops)
// ============================================================
experiment Exp_All type: gui {
    output {
        display "OSM + GTFS + Stops" type: 2d background: #white {
            // Couche 1: Routes OSM (vert)
            species osm_route aspect: default;
            
            // Couche 2: Shapes GTFS (bleu)
            species gtfs_shape aspect: default;
            
            // Couche 3: Arrêts (rouge)
            species bus_stop aspect: base;
            
            // Légende
            overlay position: {10, 10} size: {220 #px, 160 #px} 
                    background: #white transparency: 0.1 border: #black {
                draw "MODE: TOUT" at: {10 #px, 20 #px} 
                     font: font("Arial", 14, #bold) color: #black;
                draw "━━━━━━━━━━━━━━━━━━" at: {10 #px, 35 #px} color: #gray;
                
                // Ligne verte OSM
                draw line([{15 #px, 55 #px}, {35 #px, 55 #px}]) color: #green width: 3;
                draw "OSM (" + nb_osm_routes + ")" at: {45 #px, 56 #px};
                
                // Ligne bleue GTFS
                draw line([{15 #px, 75 #px}, {35 #px, 75 #px}]) color: #blue width: 3;
                draw "GTFS (" + nb_gtfs_shapes + ")" at: {45 #px, 76 #px};
                
                // Point rouge Arrêts
                draw circle(5) at: {25 #px, 95 #px} color: #red;
                draw "Arrêts (" + nb_bus_stops + ")" at: {45 #px, 96 #px};
                
                draw "━━━━━━━━━━━━━━━━━━" at: {10 #px, 115 #px} color: #gray;
                draw "3 couches superposées" at: {15 #px, 130 #px} 
                     font: font("Arial", 9) color: #gray;
                draw "Zoom pour détails" at: {15 #px, 145 #px} 
                     font: font("Arial", 9) color: #gray;
            }
        }
        
        // Monitors
        monitor "Mode" value: "OSM + GTFS + Stops" color: #black;
        monitor "Routes OSM" value: nb_osm_routes color: #green;
        monitor "Shapes GTFS" value: nb_gtfs_shapes color: #blue;
        monitor "Arrêts bus" value: nb_bus_stops color: #red;
    }
}

// ============================================================
// === EXPÉRIENCE 2: GTFS + Stops (SANS OSM)
// ============================================================
experiment Exp_GTFS_Only type: gui {
    output {
        display "GTFS + Stops" type: 2d background: #white {
            // Couche 1: Shapes GTFS (bleu)
            species gtfs_shape aspect: default;
            
            // Couche 2: Arrêts (rouge)
            species bus_stop aspect: base;
            
            // Légende
            overlay position: {10, 10} size: {220 #px, 140 #px} 
                    background: #white transparency: 0.1 border: #black {
                draw "MODE: GTFS SEULEMENT" at: {10 #px, 20 #px} 
                     font: font("Arial", 13, #bold) color: #blue;
                draw "━━━━━━━━━━━━━━━━━━" at: {10 #px, 35 #px} color: #gray;
                
                // Ligne bleue GTFS
                draw line([{15 #px, 55 #px}, {35 #px, 55 #px}]) color: #blue width: 3;
                draw "GTFS (" + nb_gtfs_shapes + ")" at: {45 #px, 56 #px};
                
                // Point rouge Arrêts
                draw circle(5) at: {25 #px, 75 #px} color: #red;
                draw "Arrêts (" + nb_bus_stops + ")" at: {45 #px, 76 #px};
                
                draw "━━━━━━━━━━━━━━━━━━" at: {10 #px, 95 #px} color: #gray;
                draw "Routes GTFS théoriques" at: {15 #px, 110 #px} 
                     font: font("Arial", 9) color: #gray;
                draw "Sans réseau OSM" at: {15 #px, 125 #px} 
                     font: font("Arial", 9) color: #gray;
            }
        }
        
        // Monitors
        monitor "Mode" value: "GTFS + Stops" color: #blue;
        monitor "Shapes GTFS" value: nb_gtfs_shapes color: #blue;
        monitor "Arrêts bus" value: nb_bus_stops color: #red;
        monitor "Routes OSM" value: "Non affichées" color: #gray;
    }
}

// ============================================================
// === EXPÉRIENCE 3: OSM + Stops (SANS GTFS)
// ============================================================
experiment Exp_OSM_Only type: gui {
    output {
        display "OSM + Stops" type: 2d background: #white {
            // Couche 1: Routes OSM (vert)
            species osm_route aspect: default;
            
            // Couche 2: Arrêts (rouge)
            species bus_stop aspect: base;
            
            // Légende
            overlay position: {10, 10} size: {220 #px, 140 #px} 
                    background: #white transparency: 0.1 border: #black {
                draw "MODE: OSM SEULEMENT" at: {10 #px, 20 #px} 
                     font: font("Arial", 13, #bold) color: #green;
                draw "━━━━━━━━━━━━━━━━━━" at: {10 #px, 35 #px} color: #gray;
                
                // Ligne verte OSM
                draw line([{15 #px, 55 #px}, {35 #px, 55 #px}]) color: #green width: 3;
                draw "OSM (" + nb_osm_routes + ")" at: {45 #px, 56 #px};
                
                // Point rouge Arrêts
                draw circle(5) at: {25 #px, 75 #px} color: #red;
                draw "Arrêts (" + nb_bus_stops + ")" at: {45 #px, 76 #px};
                
                draw "━━━━━━━━━━━━━━━━━━" at: {10 #px, 95 #px} color: #gray;
                draw "Réseau routier OSM" at: {15 #px, 110 #px} 
                     font: font("Arial", 9) color: #gray;
                draw "Sans shapes GTFS" at: {15 #px, 125 #px} 
                     font: font("Arial", 9) color: #gray;
            }
        }
        
        // Monitors
        monitor "Mode" value: "OSM + Stops" color: #green;
        monitor "Routes OSM" value: nb_osm_routes color: #green;
        monitor "Arrêts bus" value: nb_bus_stops color: #red;
        monitor "Shapes GTFS" value: "Non affichées" color: #gray;
    }
}
