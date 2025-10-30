/**
 * Modèle de matching GTFS ↔ OSM avec scoring multi-critères
 * 
 * Algorithme:
 * 1. Index spatial pour pré-filtrage
 * 2. Scoring par route OSM (couverture, direction, arrêts, connectivité)
 * 3. Détection d'ambiguïté
 * 4. Classification: ACCEPT / MEDIUM / MISSING
 */

model MatchGTFS_OSM

global {
    // ============================================================
    // === FICHIERS ===
    // ============================================================
    gtfs_file gtfs_f <- gtfs_file("../../includes/nantes_gtfs");
    shape_file boundary_shp <- shape_file("../../includes/ShapeFileNantes.shp");
    string osm_folder <- "../../results1/";
    
    geometry shape <- envelope(boundary_shp);
    
    // ============================================================
    // === PARAMÈTRES DE MATCHING ===
    // ============================================================
    float TOLERANCE_M <- 20.0;          // Buffer autour routes OSM (m)
    float ANGLE_THR <- 25.0;            // Tolérance angle direction (degrés)
    float STEP_M <- 20.0;               // Échantillonnage shape GTFS (m)
    float STOP_TOL <- 18.0;             // Distance max arrêt→route OSM (m)
    
    // Poids du scoring (total = 1.0)
    float W_COV <- 0.45;                // Poids couverture géométrique
    float W_DIR <- 0.25;                // Poids cohérence directionnelle
    float W_STOPS <- 0.25;              // Poids alignement arrêts
    float W_CONN <- 0.05;               // Poids continuité topologique
    
    // Seuils de décision
    float THRESHOLD_ACCEPT <- 0.8;      // Score minimum pour ACCEPT
    float THRESHOLD_MEDIUM <- 0.6;      // Score minimum pour MEDIUM
    float DELTA_AMBIGUITY <- 0.05;      // Écart min entre best et 2nd
    
    // ============================================================
    // === RÉSEAUX ===
    // ============================================================
    graph gtfs_network;
    graph osm_network;
    
    // ============================================================
    // === INDEX SPATIAL ===
    // ============================================================
    map<string, list<osm_route>> osm_spatial_index <- [];
    int grid_size <- 50;                // Taille de la grille d'indexation
    float cell_width;
    float cell_height;
    
    // ============================================================
    // === STATISTIQUES GLOBALES ===
    // ============================================================
    int total_shapes <- 0;
    int accepted <- 0;
    int medium <- 0;
    int missing <- 0;
    int ambiguous <- 0;
    float avg_score <- 0.0;
    float global_coverage <- 0.0;
    
    // ============================================================
    // === INITIALISATION ===
    // ============================================================
    init {
        write "╔═══════════════════════════════════════════════════════╗";
        write "║       MATCHING GTFS ↔ OSM (Multi-critères)          ║";
        write "╚═══════════════════════════════════════════════════════╝\n";
        
        // ÉTAPE 1: Charger GTFS
        do load_gtfs_network;
        
        // ÉTAPE 2: Charger OSM
        do load_osm_network;
        
        // ÉTAPE 3: Construire index spatial
        do build_spatial_index;
        
        // ÉTAPE 4: Matcher tous les shapes
        do match_all_shapes;
        
        // ÉTAPE 5: Calculer statistiques
        do compute_statistics;
        
        // ÉTAPE 6: Afficher résumé
        do print_summary;
    }
    
    // ============================================================
    // === ÉTAPE 1: CHARGER GTFS ===
    // ============================================================
    action load_gtfs_network {
        write "📍 [1/5] Chargement réseau GTFS...";
        
        create bus_stop from: gtfs_f;
        create gtfs_shape from: gtfs_f;
        
        write "  • Arrêts: " + length(bus_stop);
        write "  • Shapes: " + length(gtfs_shape);
        
        // Filtrer pour garder seulement les bus (routeType = 3)
        list<string> bus_shape_ids <- [];
        
        ask (bus_stop where (each.routeType = 3 and each.tripShapeMap != nil)) {
            loop sid over: values(tripShapeMap) {
                if (sid != nil and !(bus_shape_ids contains sid)) {
                    bus_shape_ids <- bus_shape_ids + sid;
                }
            }
        }
        
        // Marquer les shapes de bus
        ask gtfs_shape {
            is_bus <- bus_shape_ids contains shapeId;
        }
        
        total_shapes <- length(gtfs_shape where each.is_bus);
        
        // Créer le graphe GTFS
        list<geometry> gtfs_geoms <- (gtfs_shape where each.is_bus) collect each.shape;
        if (length(gtfs_geoms) > 0) {
            gtfs_network <- as_edge_graph(gtfs_geoms);
        }
        
        write "  ✅ Shapes de bus GTFS: " + total_shapes;
    }
    
    // ============================================================
    // === ÉTAPE 2: CHARGER OSM ===
    // ============================================================
    action load_osm_network {
        write "\n🗺️  [2/5] Chargement réseau OSM...";
        
        int i <- 0;
        bool continue_loading <- true;
        
        loop while: continue_loading {
            string filepath <- osm_folder + "bus_routes_part" + i + ".shp";
            
            try {
                shape_file shp <- shape_file(filepath);
                create osm_route from: shp;
                write "  • Part" + i + ": " + length(shp.contents) + " routes";
                i <- i + 1;
            } catch {
                if (i = 0) {
                    write "  ⚠️  Aucun fichier OSM trouvé";
                }
                continue_loading <- false;
            }
        }
        
        // Créer le graphe OSM
        list<geometry> osm_geoms <- osm_route collect each.shape;
        if (length(osm_geoms) > 0) {
            osm_network <- as_edge_graph(osm_geoms);
        }
        
        write "  ✅ Routes OSM chargées: " + length(osm_route);
    }
    
    // ============================================================
    // === ÉTAPE 3: CONSTRUIRE INDEX SPATIAL ===
    // ============================================================
    action build_spatial_index {
        write "\n🔍 [3/5] Construction de l'index spatial...";
        
        cell_width <- shape.width / grid_size;
        cell_height <- shape.height / grid_size;
        
        ask osm_route {
            if (shape != nil) {
                // Calculer la cellule de cette route
                point centroid <- location;
                int x <- int((centroid.x - world.shape.location.x + world.shape.width/2) / cell_width);
                int y <- int((centroid.y - world.shape.location.y + world.shape.height/2) / cell_height);
                
                // Clamp aux limites
                x <- max(0, min(grid_size - 1, x));
                y <- max(0, min(grid_size - 1, y));
                
                string key <- string(x) + "_" + string(y);
                
                // Ajouter à l'index
                if (osm_spatial_index[key] = nil) {
                    osm_spatial_index[key] <- [];
                }
                osm_spatial_index[key] <- osm_spatial_index[key] + self;
                
                // Ajouter aussi aux cellules voisines (pour sécurité)
                loop dx from: -1 to: 1 {
                    loop dy from: -1 to: 1 {
                        int nx <- x + dx;
                        int ny <- y + dy;
                        if (nx >= 0 and nx < grid_size and ny >= 0 and ny < grid_size) {
                            string nkey <- string(nx) + "_" + string(ny);
                            if (osm_spatial_index[nkey] = nil) {
                                osm_spatial_index[nkey] <- [];
                            }
                            if (!(osm_spatial_index[nkey] contains self)) {
                                osm_spatial_index[nkey] <- osm_spatial_index[nkey] + self;
                            }
                        }
                    }
                }
            }
        }
        
        int cells_used <- length(osm_spatial_index);
        float avg_routes_per_cell <- sum(osm_spatial_index collect length(each)) / cells_used;
        
        write "  ✅ Index créé: " + cells_used + " cellules";
        write "  • Moyenne: " + (avg_routes_per_cell with_precision 1) + " routes/cellule";
    }
    
    // ============================================================
    // === ÉTAPE 4: MATCHING ===
    // ============================================================
    action match_all_shapes {
        write "\n🔗 [4/5] Matching GTFS ↔ OSM...";
        
        int processed <- 0;
        list<gtfs_shape> bus_shapes <- gtfs_shape where each.is_bus;
        
        ask bus_shapes {
            if (shape != nil) {
                // Trouver les candidats OSM
                list<osm_route> candidates <- self.get_candidate_routes();
                
                if (!empty(candidates)) {
                    // Calculer score pour chaque candidat
                    float best_score <- 0.0;
                    float second_score <- 0.0;
                    osm_route best_route <- nil;
                    
                    loop r over: candidates {
                        float score <- self.compute_match_score(r);
                        
                        if (score > best_score) {
                            second_score <- best_score;
                            best_score <- score;
                            best_route <- r;
                        } else if (score > second_score) {
                            second_score <- score;
                        }
                    }
                    
                    // Stocker résultats
                    match_score <- best_score;
                    second_match_score <- second_score;
                    matched_osm <- best_route;
                    
                    // Décision finale
                    float delta <- best_score - second_score;
                    bool is_ambiguous <- delta < DELTA_AMBIGUITY and second_score > 0.3;
                    
                    if (best_score >= THRESHOLD_ACCEPT and !is_ambiguous) {
                        match_status <- "ACCEPT";
                    } else if (best_score >= THRESHOLD_MEDIUM) {
                        match_status <- is_ambiguous ? "AMBIGUOUS" : "MEDIUM";
                    } else {
                        match_status <- "MISSING";
                    }
                } else {
                    match_status <- "MISSING";
                    match_score <- 0.0;
                }
                
                processed <- processed + 1;
                
                // Progress
                if (processed mod 50 = 0) {
                    write "  • Traité: " + processed + "/" + total_shapes;
                }
            }
        }
        
        write "  ✅ Matching terminé";
    }
    
    // ============================================================
    // === ÉTAPE 5: STATISTIQUES ===
    // ============================================================
    action compute_statistics {
        write "\n📊 [5/5] Calcul des statistiques...";
        
        float sum_scores <- 0.0;
        float sum_coverage <- 0.0;
        
        ask (gtfs_shape where each.is_bus) {
            if (match_status = "ACCEPT") { 
                accepted <- accepted + 1; 
            } else if (match_status = "MEDIUM") { 
                medium <- medium + 1; 
            } else if (match_status = "AMBIGUOUS") { 
                ambiguous <- ambiguous + 1; 
            } else if (match_status = "MISSING") { 
                missing <- missing + 1; 
            }
            
            sum_scores <- sum_scores + match_score;
            
            // Calculer couverture géométrique réelle
            if (matched_osm != nil and matched_osm.shape != nil) {
                geometry mask <- buffer(matched_osm.shape, TOLERANCE_M);
                geometry covered <- intersection(shape, mask);
                float cov <- (shape.perimeter > 0) ? (covered.perimeter / shape.perimeter) : 0.0;
                sum_coverage <- sum_coverage + cov;
            }
        }
        
        avg_score <- total_shapes > 0 ? (sum_scores / total_shapes) : 0.0;
        global_coverage <- total_shapes > 0 ? (sum_coverage / total_shapes * 100.0) : 0.0;
    }
    
    // ============================================================
    // === AFFICHAGE RÉSUMÉ ===
    // ============================================================
    action print_summary {
        write "\n╔═══════════════════════════════════════════════════════╗";
        write "║                    RÉSULTATS                         ║";
        write "╠═══════════════════════════════════════════════════════╣";
        write "║ Total shapes GTFS:     " + total_shapes;
        write "║ Total shapes GTFS:     " + total_shapes;
        write "╠═══════════════════════════════════════════════════════╣";
        write "║ ✅ ACCEPTÉS:           " + accepted + " (" + (accepted * 100.0 / total_shapes) with_precision 1 + "%)      ║";
        write "║ ⚠️  MOYENS:             " + medium + " (" + (medium * 100.0 / total_shapes) with_precision 1 + "%)       ║";
        write "║ 🔀 AMBIGUS:            " + ambiguous + " (" + (ambiguous * 100.0 / total_shapes) with_precision 1 + "%)        ║";
        write "║ ❌ MANQUANTS:          " + missing + " (" + (missing * 100.0 / total_shapes) with_precision 1 + "%)       ║";
        write "╠═══════════════════════════════════════════════════════╣";
        write "║ Score moyen:           " + (avg_score with_precision 3) + "                    ║";
        write "║ Couverture globale:    " + (global_coverage with_precision 1) + "%                   ║";
        write "╚═══════════════════════════════════════════════════════╝";
        
        // Top 5 pires cas
        list<gtfs_shape> worst_cases <- (gtfs_shape where each.is_bus) sort_by each.match_score;
        
        write "\n⚠️  Top 5 pires cas (à vérifier):";
        loop i from: 0 to: min(4, length(worst_cases) - 1) {
            gtfs_shape s <- worst_cases[i];
            write "  " + (i+1) + ". Shape " + s.shapeId + ": " + 
                  (s.match_score with_precision 2) + " (" + s.match_status + ")";
        }
    }
}

// ============================================================
// === ESPÈCES ===
// ============================================================

// Arrêts GTFS
species bus_stop skills: [TransportStopSkill] {
    aspect base {
        rgb color <- (routeType = 3) ? #red : #lightblue;
        draw circle(30) color: color;
    }
}

// Shapes GTFS (avec logique de matching)
species gtfs_shape skills: [TransportShapeSkill] {
    // Attributs GTFS
    bool is_bus <- false;
    
    // Résultats du matching
    string match_status <- "PENDING";
    float match_score <- 0.0;
    float second_match_score <- 0.0;
    osm_route matched_osm <- nil;
    
    // ========================================
    // FONCTION 1: Candidats OSM (pré-filtrage spatial)
    // ========================================
    list<osm_route> get_candidate_routes {
        if (shape = nil) { return []; }
        
        // Calculer bbox élargie
        geometry bbox <- buffer(shape.envelope, TOLERANCE_M * 2);
        
        // Récupérer depuis l'index spatial
        list<osm_route> candidates <- [];
        
        // Trouver toutes les cellules qui intersectent la bbox
        loop x from: 0 to: grid_size - 1 {
            loop y from: 0 to: grid_size - 1 {
                point cell_center <- {
                    world.shape.location.x - world.shape.width/2 + (x + 0.5) * cell_width,
                    world.shape.location.y - world.shape.height/2 + (y + 0.5) * cell_height
                };
                
                if (bbox overlaps cell_center) {
                    string key <- string(x) + "_" + string(y);
                    if (osm_spatial_index[key] != nil) {
                        loop r over: osm_spatial_index[key] {
                            if (!(candidates contains r)) {
                                candidates <- candidates + r;
                            }
                        }
                    }
                }
            }
        }
        
        // Filtrer par intersection réelle
        candidates <- candidates where (each.shape intersects bbox);
        
        return candidates;
    }
    
    // ========================================
    // FONCTION 2: Score de matching global
    // ========================================
    float compute_match_score(osm_route r) {
        if (r.shape = nil or shape = nil) { return 0.0; }
        
        // Score 1: Couverture géométrique
        float score_cov <- compute_coverage_score(r);
        
        // Score 2: Cohérence directionnelle
        float score_dir <- compute_direction_score(r);
        
        // Score 3: Alignement arrêts
        float score_stops <- compute_stop_alignment_score(r);
        
        // Score 4: Continuité (simplifié pour MVP)
        float score_conn <- (score_cov > 0.5) ? 1.0 : 0.0;
        
        // Score pondéré
        float total <- W_COV * score_cov + 
                      W_DIR * score_dir + 
                      W_STOPS * score_stops + 
                      W_CONN * score_conn;
        
        return total;
    }
    
    // ========================================
    // FONCTION 3: Couverture géométrique
    // ========================================
    float compute_coverage_score(osm_route r) {
        geometry mask <- buffer(r.shape, TOLERANCE_M);
        geometry covered <- intersection(shape, mask);
        
        if (covered = nil or empty(covered.points)) {
            return 0.0;
        }
        
        float coverage <- (shape.perimeter > 0) ? 
            (covered.perimeter / shape.perimeter) : 0.0;
        
        return min(1.0, coverage);
    }
    
    // ========================================
    // FONCTION 4: Cohérence directionnelle
    // ========================================
    float compute_direction_score(osm_route r) {
        // Échantillonner le shape GTFS
        list<point> samples <- [];
        float total_length <- shape.perimeter;
        int n_samples <- max(3, int(total_length / STEP_M));
        
        loop i from: 0 to: n_samples - 1 {
            float ratio <- i / (n_samples - 1);
            point p <- shape.points[int(ratio * (length(shape.points) - 1))];
            samples <- samples + p;
        }
        
        // Pour chaque échantillon, vérifier l'orientation
        int ok <- 0;
        int total <- 0;
        
        loop i from: 0 to: length(samples) - 2 {
            point p1 <- samples[i];
            point p2 <- samples[i + 1];
            
            // Azimut GTFS local
            float theta_gtfs <- atan2(p2.y - p1.y, p2.x - p1.x) * 180.0 / #pi;
            if (theta_gtfs < 0) { theta_gtfs <- theta_gtfs + 360.0; }
            
            // Trouver segment OSM le plus proche
            point closest_osm <- r.shape.points closest_to p1;
            
            if (closest_osm distance_to p1 <= TOLERANCE_M) {
                // Trouver le segment OSM qui contient ce point
                loop j from: 0 to: length(r.shape.points) - 2 {
                    point osm1 <- r.shape.points[j];
                    point osm2 <- r.shape.points[j + 1];
                    
                    if (closest_osm = osm1 or closest_osm = osm2) {
                        // Azimut OSM
                        float theta_osm <- atan2(osm2.y - osm1.y, osm2.x - osm1.x) * 180.0 / #pi;
                        if (theta_osm < 0) { theta_osm <- theta_osm + 360.0; }
                        
                        // Différence d'angle
                        float diff <- abs(theta_gtfs - theta_osm);
                        if (diff > 180.0) { diff <- 360.0 - diff; }
                        
                        if (diff <= ANGLE_THR) {
                            ok <- ok + 1;
                        }
                        
                        total <- total + 1;
                        break;
                    }
                }
            }
        }
        
        return total > 0 ? (ok / total) : 0.0;
    }
    
    // ========================================
    // FONCTION 5: Alignement arrêts
    // ========================================
    float compute_stop_alignment_score(osm_route r) {
        // Récupérer les arrêts de ce shape
        list<bus_stop> my_stops <- bus_stop where (
            each.tripShapeMap != nil and 
            (shapeId in values(each.tripShapeMap))
        );
        
        if (empty(my_stops)) {
            return 0.5; // Score neutre si pas d'arrêts
        }
        
        // Compter arrêts proches de la route OSM
        int close_stops <- 0;
        
        loop stop over: my_stops {
            point stop_loc <- stop.location;
            float dist <- stop_loc distance_to r.shape;
            
            if (dist <= STOP_TOL) {
                close_stops <- close_stops + 1;
            }
        }
        
        float proximity_ratio <- close_stops / length(my_stops);
        
        // TODO: Vérifier ordre monotone (pour version avancée)
        // Pour MVP, on se contente de la proximité
        
        return proximity_ratio;
    }
    
    // ========================================
    // ASPECTS DE VISUALISATION
    // ========================================
    aspect default {
        if (is_bus and shape != nil) {
            draw shape color: #blue width: 2;
        }
    }
    
    aspect match_quality {
        if (is_bus and shape != nil) {
            rgb color <- match_status = "ACCEPT" ? #green :
                        (match_status = "MEDIUM" ? #orange :
                        (match_status = "AMBIGUOUS" ? #purple : #red));
            draw shape color: color width: 3;
        }
    }
    
    aspect score_heatmap {
        if (is_bus and shape != nil) {
            // Dégradé: rouge (0) → vert (1)
            int r <- int(255 * (1.0 - match_score));
            int g <- int(255 * match_score);
            rgb color <- rgb(r, g, 0);
            draw shape color: color width: 3;
        }
    }
}

// Routes OSM
species osm_route {
    aspect default {
        draw shape color: #green width: 2;
    }
    
    aspect faint {
        draw shape color: #lightgreen width: 1;
    }
}

// ============================================================
// === EXPÉRIENCE ===
// ============================================================
experiment MatchNetworks type: gui {
    parameter "Tolérance (m)" var: TOLERANCE_M min: 5.0 max: 50.0 category: "Matching";
    parameter "Angle toléré (°)" var: ANGLE_THR min: 10.0 max: 45.0 category: "Matching";
    parameter "Échantillonnage (m)" var: STEP_M min: 10.0 max: 50.0 category: "Matching";
    parameter "Tolérance arrêts (m)" var: STOP_TOL min: 10.0 max: 30.0 category: "Matching";
    
    parameter "Poids couverture" var: W_COV min: 0.0 max: 1.0 category: "Poids";
    parameter "Poids direction" var: W_DIR min: 0.0 max: 1.0 category: "Poids";
    parameter "Poids arrêts" var: W_STOPS min: 0.0 max: 1.0 category: "Poids";
    
    output {
        // ========================================
        // DISPLAY 1: Vue d'ensemble
        // ========================================
        display "Overview" type: 2d background: #white {
            species osm_route aspect: faint;
            species gtfs_shape aspect: default;
            species bus_stop aspect: base;
            
            overlay position: {10, 10} size: {280 #px, 200 #px} 
                    background: #white transparency: 0.1 border: #black {
                draw "GTFS ↔ OSM MATCHING" at: {10 #px, 20 #px} 
                     font: font("Arial", 14, #bold);
                draw "━━━━━━━━━━━━━━━━━━━━━━" at: {10 #px, 35 #px} color: #gray;
                draw "Shapes GTFS: " + total_shapes at: {15 #px, 55 #px};
                draw "Routes OSM: " + length(osm_route) at: {15 #px, 75 #px};
                draw "━━━━━━━━━━━━━━━━━━━━━━" at: {10 #px, 90 #px} color: #gray;
                draw "✅ Acceptés: " + accepted at: {15 #px, 110 #px} color: #green;
                draw "⚠️  Moyens: " + medium at: {15 #px, 130 #px} color: #orange;
                draw "🔀 Ambigus: " + ambiguous at: {15 #px, 150 #px} color: #purple;
                draw "❌ Manquants: " + missing at: {15 #px, 170 #px} color: #red;
            }
        }
        
        // ========================================
        // DISPLAY 2: Qualité du matching
        // ========================================
        display "Match Quality" type: 2d background: #white {
            species osm_route aspect: faint;
            species gtfs_shape aspect: match_quality;
            
            overlay position: {10, 10} size: {240 #px, 160 #px} 
                    background: #white transparency: 0.1 border: #black {
                draw "QUALITÉ MATCHING" at: {10 #px, 20 #px} 
                     font: font("Arial", 13, #bold);
                draw "━━━━━━━━━━━━━━━━━━━━" at: {10 #px, 35 #px} color: #gray;
                
                draw rectangle(15, 15) at: {20 #px, 55 #px} color: #green;
                draw "ACCEPT (≥80%)" at: {42 #px, 58 #px};
                
                draw rectangle(15, 15) at: {20 #px, 75 #px} color: #orange;
                draw "MEDIUM (60-80%)" at: {42 #px, 78 #px};
                
                draw rectangle(15, 15) at: {20 #px, 95 #px} color: #purple;
                draw "AMBIGUOUS" at: {42 #px, 98 #px};
                
                draw rectangle(15, 15) at: {20 #px, 115 #px} color: #red;
                draw "MISSING (<60%)" at: {42 #px, 118 #px};
                
                draw "━━━━━━━━━━━━━━━━━━━━" at: {10 #px, 130 #px} color: #gray;
                draw "Score moyen: " + (avg_score with_precision 2) 
                     at: {15 #px, 148 #px} font: font("Arial", 11, #bold);
            }
        }
        
        // ========================================
        // DISPLAY 3: Heatmap des scores
        // ========================================
        display "Score Heatmap" type: 2d background: #white {
            species osm_route aspect: faint;
            species gtfs_shape aspect: score_heatmap;
            
            overlay position: {10, 10} size: {220 #px, 140 #px} 
                    background: #white transparency: 0.1 border: #black {
                draw "SCORE HEATMAP" at: {10 #px, 20 #px} 
                     font: font("Arial", 13, #bold);
                draw "━━━━━━━━━━━━━━━━━━" at: {10 #px, 35 #px} color: #gray;
                
                // Gradient legend
                loop i from: 0 to: 9 {
                    float ratio <- i / 10.0;
                    int r <- int(255 * (1.0 - ratio));
                    int g <- int(255 * ratio);
                    rgb col <- rgb(r, g, 0);
                    draw rectangle(15, 10) at: {20 #px + i * 16, 60 #px} color: col;
                }
                
                draw "0.0" at: {15 #px, 78 #px} font: font("Arial", 9);
                draw "1.0" at: {180 #px, 78 #px} font: font("Arial", 9);
                
                draw "━━━━━━━━━━━━━━━━━━" at: {10 #px, 95 #px} color: #gray;
                draw "Couverture: " + (global_coverage with_precision 1) + "%" 
                     at: {15 #px, 115 #px} font: font("Arial", 11, #bold);
            }
        }
        
        // ========================================
        // MONITORS
        // ========================================
        monitor "Total shapes" value: total_shapes;
        monitor "Acceptés" value: accepted color: #green;
        monitor "Moyens" value: medium color: #orange;
        monitor "Ambigus" value: ambiguous color: #purple;
        monitor "Manquants" value: missing color: #red;
        monitor "Score moyen" value: avg_score with_precision 3;
        monitor "Couverture globale" value: string(global_coverage with_precision 1) + "%";
    }
}
