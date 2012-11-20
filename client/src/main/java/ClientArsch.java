import org.apache.http.HttpEntity;
import org.apache.http.HttpResponse;
import org.apache.http.client.methods.HttpPost;
import org.apache.http.impl.client.DefaultHttpClient;
import org.apache.http.impl.conn.PoolingClientConnectionManager;

import java.io.IOException;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ScheduledFuture;
import java.util.concurrent.TimeUnit;

/**
 * @author Tobi Knaup
 */
public class ClientArsch {

  public static final int NUM_THREADS = 10;
  public static final int INTERVAL_MS = 25;

  private final ScheduledExecutorService scheduler = Executors.newScheduledThreadPool(1);

  public static void main(String[] args) {
    new ClientArsch().run();
  }

  public void run() {

//    final PoolingClientConnectionManager cm = new PoolingClientConnectionManager();
//    cm.setMaxTotal(100);

    for (int i = 0; i < NUM_THREADS; i++) {
      scheduler.scheduleAtFixedRate(new PostThread(String.valueOf(i)), 0, INTERVAL_MS, TimeUnit.MILLISECONDS);
    }

//    final ScheduledFuture<?> clientHandle =
  }

  class PostThread implements Runnable {

    DefaultHttpClient httpClient;
    HttpPost httpPost;
    String id;

    public PostThread(String id) {
      super();
      this.id = id;
      this.httpClient = new DefaultHttpClient();
      this.httpPost = new HttpPost("http://localhost:8088/search/test");
    }

    public void run() {
      try {
        Long tic = System.nanoTime();
        HttpResponse response = httpClient.execute(httpPost);
        Long toc = System.nanoTime();

        System.out.printf("%s\t%d\t%d\t%d\n", id, (toc / 1000L), (toc - tic) / 1000L, response.getStatusLine().getStatusCode());

        HttpEntity entity = response.getEntity();
        entity.getContent().close(); // release client
      } catch (IOException e) {
        e.printStackTrace();
      }
    }
  }

}
