/**
 * Name: ExportBusShapesOnly
 * Description: Export uniquement les shapes des lignes de bus (filtré)
 * Date: 2025-10-10
 */

model ExportBusShapesOnly

global {
    gtfs_file gtfs_f <- gtfs_file("../../includes/nantes_gtfs");
    shape_file boundary_shp <- shape_file("../../includes/ShapeFileNantes.shp");
    geometry shape <- envelope(boundary_shp);
    
    string results_folder <- "../../results2/";
    int max_shapes_per_file <- 500;
    
    init {
        write "=== EXPORT SHAPES BUS UNIQUEMENT ===";
        
        // Charger toutes les shapes GTFS
        create transport_shape from: gtfs_f;
        write "Total shapes chargees : " + length(transport_shape);
        
        // Créer agents seulement pour les BUS (route_type = 3)
        ask bus_shape_export { do die; }
        
        int bus_count <- 0;
        loop s over: transport_shape {
            if s.shape != nil and s.routeType = 3 {
                create bus_shape_export {
                    shape_id <- s.shapeId;
                    route_id <- s.routeId;
                    length_m <- s.shape.perimeter;
                    shape <- s.shape;
                }
                bus_count <- bus_count + 1;
            }
        }
        
        write "Shapes BUS filtrees : " + bus_count;
        
        // Exporter
        do export_bus_shapes;
        
        write "=== TERMINE ===";
    }
    
    action export_bus_shapes {
    int file_counter <- 0;
    int count <- 0;
    list<bus_shape_export> batch <- [];
    
    loop s over: bus_shape_export {
        batch << s;  // ← CORRIGÉ
        count <- count + 1;
        
        if count >= max_shapes_per_file {
            do save_batch(file_counter, batch);
            file_counter <- file_counter + 1;
            count <- 0;
            batch <- [];
        }
    }
    
    // Sauver dernier batch
    if !empty(batch) {
        do save_batch(file_counter, batch);
    	}
	}
    
    action save_batch(int num, list<bus_shape_export> agents_to_save) {
        string filename <- results_folder + "bus_shapes_part" + num + ".shp";
        
        try {
            save agents_to_save to: filename format: "shp"
                attributes: [
                    "shape_id"::shape_id,
                    "route_id"::route_id,
                    "length_m"::length_m
                ];
            write "Fichier " + num + " : " + length(agents_to_save) + " shapes BUS";
        } catch {
            write "Erreur fichier " + num;
        }
    }
}

species transport_shape skills: [TransportShapeSkill] {
    aspect base {
        rgb line_color <- routeType = 3 ? #blue : #gray;
        draw shape color: line_color width: 2;
    }
}

species bus_shape_export {
    int shape_id;
    string route_id;
    float length_m;
    
    aspect base {
        draw shape color: #green width: 3;
    }
}

experiment ExportBusShapes type: gui {
    output {
        display "Shapes Bus" background: #white {
            species transport_shape aspect: base transparency: 0.5;
            species bus_shape_export aspect: base;
        }
        
        monitor "Total shapes" value: length(transport_shape);
        monitor "Shapes BUS" value: length(bus_shape_export);
    }
}