import java.io.*;
import java.util.*;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.awt.Graphics;
import java.awt.Image;
import java.awt.image.BufferedImage;
import javax.imageio.ImageIO;

public class CreateFile{
	public static void main(String[] args){
		CreateFile cf = new CreateFile();
		try{
			cf.readFile(args[0]);
			//System.out.println(args[0]);
		}catch(IOException e){}
	}

	private void readFile(String filename)throws IOException{
		BufferedImage image = ImageIO.read(new File(filename));
		//byte[][] pixels = new byte[image.getWidth()][];

		for (int x = 0; x < image.getWidth(); x++) {
		    for (int y = 0; y < image.getHeight(); y++) {
		        //pixels[x][y] = (byte) (image.getRGB(x, y) == 0xFFFFFFFF ? 0 : 1);
		        /*if(image.getRGB(x,y) == -1) System.out.print(1);
		        else System.out.print(0);*/
		        System.out.print(image.getRGB(x,y)+ " ");
		    }
		    System.out.println();
		}
	}
}