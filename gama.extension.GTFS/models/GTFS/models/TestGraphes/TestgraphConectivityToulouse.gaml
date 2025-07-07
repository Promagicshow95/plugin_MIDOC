model TestConnectiviteShapes

global {
    string gtfs_dir <- "../../includes/tisseo_gtfs_v2"; // Adapter le chemin si besoin
    gtfs_file gtfs_f;
    int nb_shapes_total <- 0;
    int nb_shapes_isolees <- 0;
    int nb_shapes_connectees <- 0;
    map<point, int> extremite_count <- []; // Compte le nombre de shapes qui ont ce point comme extrémité
    shape_file boundary_shp <- shape_file("../../includes/shapeFileToulouse.shp");
    geometry shape <- envelope(boundary_shp);

    init {
        write "🚍 Test connectivité shapes - GTFS=" + gtfs_dir;
        gtfs_f <- gtfs_file(gtfs_dir);
        if (gtfs_f = nil) {
            write "❌ Erreur : impossible de charger le GTFS.";
            do die;
        }
        create transport_shape from: gtfs_f;
        nb_shapes_total <- length(transport_shape);
        write "📊 " + string(nb_shapes_total) + " shapes chargées.";
    }

    // Test au cycle 2 pour laisser le temps de charger les shapes
    reflex test_connectivite when: cycle = 2 {
        extremite_count <- [];
        nb_shapes_isolees <- 0;
        nb_shapes_connectees <- 0;

        // 1. Compter toutes les extrémités de toutes les shapes
        ask transport_shape {
            if (shape != nil and length(shape.points) > 1) {
                point p0 <- shape.points[0];
                point pN <- last(shape.points);
                extremite_count[p0] <- (extremite_count[p0] = nil ? 1 : extremite_count[p0] + 1);
                extremite_count[pN] <- (extremite_count[pN] = nil ? 1 : extremite_count[pN] + 1);
            }
        }

        // 2. Pour chaque shape, déterminer si elle est isolée (aucune de ses extrémités n'est partagée)
        ask transport_shape {
            if (shape != nil and length(shape.points) > 1) {
                point p0 <- shape.points[0];
                point pN <- last(shape.points);

                bool partage0 <- extremite_count[p0] > 1;
                bool partageN <- extremite_count[pN] > 1;

                if (partage0 or partageN) {
                    self.color <- #green;
                    nb_shapes_connectees <- nb_shapes_connectees + 1;
                } else {
                    self.color <- #red;
                    nb_shapes_isolees <- nb_shapes_isolees + 1;
                }
            } else {
                self.color <- #gray;
            }
        }

        write "══════════════════════════════════════════════════";
        write "Shapes connectées (au moins une extrémité partagée): " + string(nb_shapes_connectees);
        write "Shapes isolées (aucune extrémité partagée):        " + string(nb_shapes_isolees);
        write "══════════════════════════════════════════════════";
    }
}

species transport_shape skills: [TransportShapeSkill] {
    rgb color <- #gray; // Par défaut
    aspect base {
        draw shape color: color width: 3;
    }
}

experiment TestConnectivite type: gui {
    parameter "Dossier GTFS" var: gtfs_dir category: "Configuration";
    output {
        monitor "Shapes totales" value: nb_shapes_total;
        monitor "Shapes connectées" value: nb_shapes_connectees;
        monitor "Shapes isolées" value: nb_shapes_isolees;
        display "Carte du réseau" {
            species transport_shape aspect: base;
        }
    }
}
