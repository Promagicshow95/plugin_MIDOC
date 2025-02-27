model GTFSreader

global {
    // Path to the GTFS file
    gtfs_file gtfs_f <- gtfs_file("../../includes/tisseo_gtfs_v2");	
    shape_file boundary_shp <- shape_file("../../includes/boundaryTLSE-WGS84PM.shp");

    // Geometry of the boundary
    geometry shape <- envelope(boundary_shp);

    //tolerance for reconnecting nodes
	float tolerance <- 3.0;
	
	//if true, split the lines at their intersection
	bool split_lines <- true;
	
	//if true, keep only the main connected components of the network
	bool reduce_to_main_connected_components <- true;
    

    // Initialization section
    init {
        write "Loading GTFS contents from: " + gtfs_f;
        
        // Create transport_shape agents from the GTFS data
        create transport_shape from: gtfs_f {
         
        }
        
         // Nettoyage du réseau de transport
        list<geometry> clean_lines <- clean_network(transport_shape collect each.shape, tolerance, split_lines, reduce_to_main_connected_components) ;
        
         // **Créer une correspondance entre chaque shape et son routeType**
        map<geometry, int> shape_to_routeType <- map(transport_shape collect (each.shape::each.routeType));
        
         // Création des routes à partir des géométries nettoyées
        create road from: clean_lines{
        	// Calculer le centroïde de la route actuelle
    		geometry road_centroid <- self.shape.centroid;
    		
    		// Trouver le transport_shape le plus proche basé sur le centroïde
    		transport_shape closest_shape <- road_centroid closest_to transport_shape;
    		
    		// Assigner le routeType du transport_shape le plus proche à la route
    		if (closest_shape != nil) {
        	self.routeType <- closest_shape.routeType;
    		} else {
        	self.routeType <- -1; // Valeur par défaut si aucun transport_shape n'est trouvé
    		}
        }
        
		//save building geometry into the shapefile: add the attribute TYPE which value is set by the type variable of the building agent and the attribute ID 

        //save road to:"../../includes/cleaned_network.shp" format:"shp" attributes: ["ID":: int(self), "routeType"::int];
        
    }
}

// Species representing each transport shape
species transport_shape skills: [TransportShapeSkill] {

    init {
       
    }

    // Aspect to visualize the shape as a polygon
    aspect base {
       draw shape color: #green;
    }
}

species road {
	aspect default {
		draw shape color: #black;
	}
	
	int routeType; 
	 init {
        
    }
}


// GUI-based experiment for visualization
experiment GTFSExperiment type: gui {
    
    // Output section to define the display
    output {
        // Display the transport shapes on the map
        display "Transport Shapes" {
            species transport_shape aspect: base;
            species road aspect: default;
        }
    }
}

