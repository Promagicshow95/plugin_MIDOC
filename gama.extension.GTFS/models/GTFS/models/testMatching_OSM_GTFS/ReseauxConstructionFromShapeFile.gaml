model BusNetworkSimple

global {
    // Chemin vers les shapefiles
    string results_folder <- "../../results1/";
    
    // Enveloppe (optionnelle)
    file boundary <- shape_file("../../includes/ShapeFileNantes.shp");
    geometry shape <- envelope(boundary);
    
    // Graphe routier
    graph road_network;
    
    init {
        write "=== CHARGEMENT RÉSEAU BUS ===";
        
        // Charger tous les fichiers bus_routes_part0 à part8
        int i <- 0;
        bool continue_loading <- true;
        
        loop while: continue_loading {
            string filepath <- results_folder + "bus_routes_part" + i + ".shp";
            
            try {
                shape_file shp <- shape_file(filepath);
                create bus_route from: shp;
                write "✅ Chargé: part" + i + " - " + length(shp.contents) + " routes";
                i <- i + 1;
            } catch {
                if (i = 0) {
                    write "❌ Aucun fichier trouvé dans " + results_folder;
                } else {
                    write "✅ Fin du chargement (" + i + " fichiers)";
                }
                continue_loading <- false;
            }
        }
        
        // Créer le graphe routier depuis toutes les routes
        if (length(bus_route) > 0) {
            road_network <- as_edge_graph(bus_route);
            write "✅ Graphe créé avec " + length(bus_route) + " routes";
        }
        
        write "=== RÉSEAU CHARGÉ ===";
    }
}

// Espèce pour les routes de bus
species bus_route {
    aspect default {
        draw shape color: #green width: 2;
    }
}

// Expérience
experiment BusNetwork type: gui {
    output {
        display "Réseau de Bus" type: 2d background: #white {
            species bus_route aspect: default;
        }
        
        monitor "Nombre de routes" value: length(bus_route);
    }
}