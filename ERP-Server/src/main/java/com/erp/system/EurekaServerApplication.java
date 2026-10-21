package com.erp.system;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.cloud.netflix.eureka.server.EnableEurekaServer; // Pastikan NETFLIX (ada huruf 'L')

@SpringBootApplication
@EnableEurekaServer // Anotasi ini yang membuat aplikasi menjadi 'Buku Telepon'
public class EurekaServerApplication {

    public static void main(String[] args) {
        SpringApplication.run(EurekaServerApplication.class, args);
    }

}