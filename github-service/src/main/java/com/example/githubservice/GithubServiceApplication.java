package com.example.githubservice;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class GithubServiceApplication {

    public static void main(String[] args) {
        new SpringApplication(GithubServiceApplication.class).run(args);
    }
}
