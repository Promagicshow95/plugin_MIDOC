/**
* Name: NewModel
* Based on the internal empty template. 
* Author: tiend
* Tags: 
*/

model ShapeStopProjectionTest

global {
    // === CONFIGURATION DE LA PROJECTION ===
    // Utilisation de Web Mercator comme dans votre exemple, ou Lambert-93 pour la France
    string projection_crs <- "EPSG:3857"; // Web Mercator
    // Alternative pour la France : "EPSG:2154" (Lambert-93)
    
    // === FICHIERS DE DONNÉES ===
    gtfs_file gtfs_f <- gtfs_file("../../includes/ToulouseFilter_gtfs_cleaned");
    shape_file boundary_shp <- shape_file("../../includes/ToulouseFilter_wgs84.shp");
    geometry shape <- envelope(boundary_shp);
    
    // === VARIABLES DE TEST ===
    int total_stops <- 0;
    int total_shapes <- 0;
    float coherence_tolerance <- 100.0; // Distance en mètres pour considérer qu'un stop est "sur" une shape
    int coherent_stops <- 0;
    list<bus_stop> problematic_stops <- [];
    
    // === STATISTIQUES DE COHÉRENCE ===
    float min_distance_to_shape <- 999999.0;
    float max_distance_to_shape <- 0.0;
    float avg_distance_to_shape <- 0.0;
    float total_distance_sum <- 0.0; // Fixed: Added proper variable declaration
    
    init {
        write "=== TEST DE COHÉRENCE SPATIALE SHAPE-STOP ===";
        write "📍 Projection utilisée : " + projection_crs;
        write "📏 Tolérance de cohérence : " + string(coherence_tolerance) + " mètres"; // Fixed: Added string conversion
        write "";
        
        // Définir la projection avant de charger les données
        write "🔧 Configuration de la projection...";
        
        write "📂 Chargement des données GTFS depuis : tisseo_gtfs_v2";
        
        // === CRÉATION DES ARRÊTS ===
        write "🚏 Création des arrêts de bus...";
        create bus_stop from: gtfs_f {
    // Personnalisation de l'affichage
    if stopName != nil {
        display_name <- stopName;
        // Identifier les arrêts importants
        if contains(stopName, "Capitole") or contains(stopName, "Gare") {
            color <- #red;
            size <- 150.0;
            is_important <- true;
        }
    } else {
        display_name <- "Arrêt_" + stopId;
    }
}
        
        // Compter APRÈS la création
total_stops <- length(bus_stop);
write "✅ " + string(total_stops) + " arrêts créés";
        
        // === CRÉATION DES SHAPES ===
        write "📐 Création des formes de transport...";
        create transport_shape from: gtfs_f {
    // Personnalisation selon l'ID de la shape
    if shapeId != nil {
        // Différencier les couleurs selon les lignes
        int shape_hash <- int(shapeId) mod 8;
        switch shape_hash {
            match 0 { line_color <- #blue; }
            match 1 { line_color <- #red; }
            match 2 { line_color <- #green; }
            match 3 { line_color <- #orange; }
            match 4 { line_color <- #purple; }
            match 5 { line_color <- #cyan; }
            match 6 { line_color <- #magenta; }
            default { line_color <- #gray; }
        }
    }
}

// Compter APRÈS la création
total_shapes <- length(transport_shape);
write "✅ " + string(total_shapes) + " formes de transport créées";
        
        // === INITIALISATION DES AGENTS ===
        ask bus_stop { 
            do customInit;
        }
        
        ask transport_shape {
            do customInit;
        }
        
        write "🚀 Modèle initialisé - Analyse de cohérence en cours...";
    }
    
    // === ANALYSE DE COHÉRENCE SPATIALE ===
    reflex analyze_coherence when: cycle = 1 {
        write "=== ANALYSE DE COHÉRENCE SPATIALE ===";
        
        total_distance_sum <- 0.0; // Fixed: Use proper variable name
        coherent_stops <- 0;
        problematic_stops <- [];
        min_distance_to_shape <- 999999.0;
        max_distance_to_shape <- 0.0;
        
        ask bus_stop {
            float min_dist_to_any_shape <- 999999.0;
            transport_shape closest_shape <- nil;
            
            // Trouver la shape la plus proche
            ask transport_shape {
                if shape != nil {
                    float dist <- myself.location distance_to shape;
                    if dist < min_dist_to_any_shape {
                        min_dist_to_any_shape <- dist;
                        closest_shape <- self;
                    }
                }
            }
            
            // Enregistrer la distance
            distance_to_closest_shape <- min_dist_to_any_shape;
            
            // Statistiques globales
            myself.total_distance_sum <- myself.total_distance_sum + min_dist_to_any_shape; // Fixed: Use proper variable name
            if min_dist_to_any_shape < myself.min_distance_to_shape {
                myself.min_distance_to_shape <- min_dist_to_any_shape;
            }
            if min_dist_to_any_shape > myself.max_distance_to_shape {
                myself.max_distance_to_shape <- min_dist_to_any_shape;
            }
            
            // Test de cohérence
            if min_dist_to_any_shape <= coherence_tolerance {
                myself.coherent_stops <- myself.coherent_stops + 1;
                is_coherent <- true;
                color <- is_important ? #red : #green;
            } else {
                is_coherent <- false;
                myself.problematic_stops <- myself.problematic_stops + self;
                color <- #orange; // Arrêts problématiques en orange
                write "⚠️  Arrêt incohérent : " + display_name + 
                      " (distance: " + string(int(min_dist_to_any_shape)) + "m)"; // Fixed: Added string conversion
            }
        }
        
        // Calcul de la moyenne
        avg_distance_to_shape <- total_distance_sum / total_stops; // Fixed: Use proper variable name
        
        // === AFFICHAGE DES RÉSULTATS ===
        write "📊 RÉSULTATS DE L'ANALYSE :";
        write "   🚏 Arrêts analysés : " + string(total_stops); // Fixed: Added string conversion
        write "   📐 Shapes analysées : " + string(total_shapes); // Fixed: Added string conversion
        write "   ✅ Arrêts cohérents : " + string(coherent_stops) + " (" + 
              string(int((coherent_stops / total_stops) * 100)) + "%)"; // Fixed: Added string conversion
        write "   ⚠️  Arrêts problématiques : " + string(length(problematic_stops)); // Fixed: Added string conversion
        write "";
        write "📏 DISTANCES :";
        write "   🎯 Distance minimale : " + string(int(min_distance_to_shape)) + " mètres"; // Fixed: Added string conversion
        write "   📊 Distance moyenne : " + string(int(avg_distance_to_shape)) + " mètres"; // Fixed: Added string conversion
        write "   📈 Distance maximale : " + string(int(max_distance_to_shape)) + " mètres"; // Fixed: Added string conversion
        write "";
        
        // === ÉVALUATION GLOBALE ===
        float coherence_rate <- (coherent_stops / total_stops) * 100;
        if coherence_rate >= 90 {
            write "🎉 EXCELLENT : Cohérence spatiale très bonne (" + string(int(coherence_rate)) + "%)"; // Fixed: Added string conversion
        } else if coherence_rate >= 70 {
            write "✅ BON : Cohérence spatiale acceptable (" + string(int(coherence_rate)) + "%)"; // Fixed: Added string conversion
        } else if coherence_rate >= 50 {
            write "⚠️  MOYEN : Cohérence spatiale à améliorer (" + string(int(coherence_rate)) + "%)"; // Fixed: Added string conversion
        } else {
            write "❌ PROBLÈME : Cohérence spatiale insuffisante (" + string(int(coherence_rate)) + "%)"; // Fixed: Added string conversion
        }
        
        if avg_distance_to_shape > coherence_tolerance {
            write "🔍 RECOMMANDATION : Vérifier la projection ou la qualité des données GTFS";
        }
    }
    
    // === MONITORING CONTINU ===
    reflex show_stats when: cycle mod 10 = 0 and cycle > 1 {
        write "📊 Stats (Cycle " + string(cycle) + ") - Cohérents: " + string(coherent_stops) + "/" + string(total_stops) + 
              " (" + string(int((coherent_stops / total_stops) * 100)) + "%)"; // Fixed: Added string conversions
    }
}

// === SPECIES ARRÊT DE BUS ===
species bus_stop skills: [TransportStopSkill] {
    rgb color <- #blue;
    float size <- 100.0;
    string display_name;
    bool is_important <- false;
    bool is_coherent <- false;
    float distance_to_closest_shape <- 0.0;
    
    action customInit {
        if stopName != nil and stopName != "" {
            display_name <- stopName;
        } else if stopId != nil {
            display_name <- "Arrêt_" + stopId;
        } else {
            display_name <- "Arrêt_" + string(self);
        }
    }
    
    aspect base {
        if location != nil {
            draw circle(size) at: location color: color border: #black;
        }
    }
    
    aspect detailed {
        if location != nil {
            draw circle(size) at: location color: color border: #black;
            if display_name != nil {
                draw display_name color: #black font: font("Arial", 10, #bold) 
                     at: location + {0, size + 15};
            }
        }
    }
    
    aspect coherence_analysis {
        if location != nil {
            // Taille selon la cohérence
            float display_size <- is_coherent ? size : size * 1.5;
            draw circle(display_size) at: location color: color border: #black;
            
            if display_name != nil {
                rgb text_color <- is_coherent ? #darkgreen : #red;
                draw display_name color: text_color font: font("Arial", 9, #bold) 
                     at: location + {0, display_size + 15};
            }
            
            // Afficher la distance pour les arrêts problématiques
            if not is_coherent {
                string dist_text <- string(int(distance_to_closest_shape)) + "m"; // Fixed: Added string conversion
                draw dist_text color: #red font: font("Arial", 8) 
                     at: location + {0, display_size + 30};
            }
        }
    }
}

// === SPECIES FORME DE TRANSPORT ===
species transport_shape skills: [TransportShapeSkill] {
    rgb line_color <- #blue;
    float line_width <- 3.0;
    
    action customInit {
        // Custom initialization if needed
    }
    
    aspect base {
        if shape != nil {
            draw shape color: line_color width: line_width;
        }
    }
    
    aspect detailed {
        if shape != nil {
            draw shape color: line_color width: line_width;
            
            // Afficher l'ID de la shape si disponible
            if shapeId != nil and shape != nil {
                point shape_center <- centroid(shape);
                draw ("Shape: " + shapeId) color: line_color font: font("Arial", 8) 
                     at: shape_center;
            }
        }
    }
}

// === EXPÉRIENCE DE VISUALISATION ===
experiment ShapeStopCoherenceTest type: gui {
    parameter "Projection CRS" var: projection_crs among: ["EPSG:3857", "EPSG:2154", "EPSG:4326"] 
              category: "Projection";
    parameter "Tolérance de cohérence (m)" var: coherence_tolerance min: 10.0 max: 500.0 
              category: "Analyse";
    
    output {
        // === DISPLAY PRINCIPAL : ANALYSE DE COHÉRENCE ===
        display "Test de Cohérence Shape-Stop" type: 2d {
            // Fond avec les limites administratives
            graphics "Boundary" {
                if boundary_shp != nil {
                    draw boundary_shp color: #lightgray border: #black ;
                }
            }
            
            // Shapes de transport (dessiner en premier, en arrière-plan)
            species transport_shape aspect: base transparency: 0.6;
            
            // Arrêts de bus (dessiner par-dessus)
            species bus_stop aspect: coherence_analysis;
            
            // Légende et informations
            overlay position: {10, 10} size: {350 #px, 200 #px} 
                     background: #white transparency: 0.9 {
                draw "=== TEST DE COHÉRENCE SHAPE-STOP ===" at: {5#px, 15#px} 
                     color: #black font: font("Arial", 11, #bold);
                draw ("Projection : " + projection_crs) at: {5#px, 35#px} color: #blue;
                draw ("Arrêts : " + string(total_stops) + " | Shapes : " + string(total_shapes)) at: {5#px, 55#px} color: #black; // Fixed: Added string conversion
                draw ("Cohérents : " + string(coherent_stops) + " (" + 
                      string(int((coherent_stops > 0 ? (coherent_stops / total_stops) * 100 : 0))) + "%)")
                     at: {5#px, 75#px} color: #green; // Fixed: Added string conversion
                draw ("Problématiques : " + string(length(problematic_stops))) at: {5#px, 95#px} color: #orange; // Fixed: Added string conversion
                draw ("Tolérance : " + string(coherence_tolerance) + "m") at: {5#px, 115#px} color: #purple; // Fixed: Added string conversion
                
                // Légende des couleurs
                draw "🟢 Cohérent  🟠 Problématique  🔴 Important" at: {5#px, 140#px} 
                     color: #black font: font("Arial", 9);
                draw ("Distance moy : " + string(int(avg_distance_to_shape)) + "m") at: {5#px, 160#px} color: #darkblue; // Fixed: Added string conversion
            }
        }
        
        
        // === GRAPHIQUE : ANALYSE DES DISTANCES ===
        display "Analyse des Distances" {
            chart "Distribution des Distances Stop-Shape" type: histogram {
                if total_stops > 0 {
                    // Créer des bins pour l'histogramme
                    list<float> distances <- bus_stop collect each.distance_to_closest_shape;
                    
                    int coherent_count <- length(distances where (each <= coherence_tolerance));
                    int problematic_count <- length(distances where (each > coherence_tolerance));
                    
                    data "Cohérents (≤" + string(coherence_tolerance) + "m)" value: coherent_count color: #green; // Fixed: Added string conversion
                    data "Problématiques (>" + string(coherence_tolerance) + "m)" value: problematic_count color: #red; // Fixed: Added string conversion
                }
            }
        }
        
        // === MONITOR : CONSOLE DE DIAGNOSTIC ===
        monitor "Arrêts totaux" value: total_stops;
        monitor "Shapes totales" value: total_shapes;
        monitor "Arrêts cohérents" value: coherent_stops;
        monitor "Taux de cohérence (%)" value: total_stops > 0 ? int((coherent_stops / total_stops) * 100) : 0;
        monitor "Distance moyenne (m)" value: int(avg_distance_to_shape);
        monitor "Distance max (m)" value: int(max_distance_to_shape);
    }
}