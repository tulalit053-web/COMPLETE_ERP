package com.erp.system;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.cloud.client.discovery.EnableDiscoveryClient;

@SpringBootApplication
@EnableDiscoveryClient
public class ErpGatewayApplication {

    public static void main(String[] args) {
        SpringApplication.run(ErpGatewayApplication.class, args);
    }

}