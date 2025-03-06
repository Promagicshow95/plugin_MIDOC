/**
* Name: transportShape
* Based on the internal empty template. 
* Author: tiend
* Tags: 
*/


model transportTrip

global {
	gtfs_file gtfs_f <- gtfs_file("../../includes/tisseo_gtfs_v2");	
    shape_file boundary_shp <- shape_file("../../includes/boundaryTLSE-WGS84PM.shp");
    shape_file cleaned_road_shp <- shape_file("../../includes/cleaned_network.shp");
    geometry shape <- envelope(boundary_shp);
    init{
    	create transport_trip from: gtfs_f {
         	
        }
        
        create road from: cleaned_road_shp{
        	if(self.shape intersects world.shape){}
        	else {
        		write "Loading GTFS contents from: " + self.shape;
        		do die;
        	}
      
        }
    }
}

species transport_trip skills: [TransportTripSkill] {

    init {
       
    }

}

species road {

    int routeType; 
    int shapeId;
}

experiment GTFSExperiment type: gui {

}

