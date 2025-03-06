model GTFSreader

global {
    // Path to the GTFS file
    gtfs_file gtfs_f <- gtfs_file("../../includes/tisseo_gtfs_v2");	
    shape_file boundary_shp <- shape_file("../../includes/boundaryTLSE-WGS84PM.shp");
    shape_file cleaned_road_shp <- shape_file("../../includes/cleaned_network.shp");

    // Geometry of the boundary
    geometry shape <- envelope(boundary_shp);
    

    // Initialization section
    init {
        write "Loading GTFS contents from: " + gtfs_f;
        
        // Create transport_shape agents from the GTFS data
        create transport_shape from: gtfs_f {
         
        }
        
         // Nettoyage du réseau de transport
        
         // **Créer une correspondance entre chaque shape et son routeType**
        map<geometry, int> shape_to_routeType <- map(transport_shape collect (each.shape::each.routeType));
        
         // Création des routes à partir des géométries nettoyées
        create road from: cleaned_road_shp{
        	if(self.shape intersects world.shape){}
        	else {
        		write "kill " + self;
        		do die;
        	}
      
        }
        
    }
}

// Species representing each transport shape
species transport_shape skills: [TransportShapeSkill] {

    init {
       
    }

    // Aspect to visualize the shape as a polygon
//    aspect base {
//       draw shape color: #black;
//    }
}

species road {
	aspect default {
		if (routeType = -1) { draw shape color: rgb(128, 128, 128); } // Gris
		if (routeType = 0)  { draw shape color: rgb(0, 0, 255); }    // Bleu
		if (routeType = 1)  { draw shape color: rgb(255, 0, 0); }    // Rouge
		if (routeType = 3)  { draw shape color: rgb(0, 255, 0); }    // Vert
		if (routeType = 6)  { draw shape color: rgb(255, 165, 0); }  // Orange
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
//            species transport_shape aspect: base;
            species road aspect: default;
        }
    }
}

