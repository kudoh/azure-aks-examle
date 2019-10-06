package com.example.githubservice;

import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.web.client.RestTemplateBuilder;
import org.springframework.core.ParameterizedTypeReference;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpMethod;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.client.RestTemplate;
import org.springframework.web.util.UriComponents;
import org.springframework.web.util.UriComponentsBuilder;

import java.util.List;
import java.util.Map;
import java.util.stream.Stream;

@RestController
@RequiredArgsConstructor
@Slf4j
@RequestMapping("github")
public class GithubController {

    private final ObjectMapper objectMapper ;
    private final  GithubProps props;

    @GetMapping("repos")
    Stream<Repository> find(@RequestParam("query") String word) {

        UriComponents uri = UriComponentsBuilder.fromUriString(props.getBaseUrl())
                .path(props.getRepoSearchPath())
                .queryParam("q", word)
                .build();
        log.info("retrieving repositories from github for {}", uri.toUriString());
        RestTemplate restTemplate = new RestTemplateBuilder()
                .basicAuthentication(props.getUser(), props.getPassword())
                .build();

        ResponseEntity<Map<String, Object>> responseEntity = restTemplate.exchange(uri.toUri(), HttpMethod.GET,
                HttpEntity.EMPTY,
                new ParameterizedTypeReference<Map<String, Object>>() {});

        List<Object> items = (List<Object>)responseEntity.getBody().get("items");

        return items.stream().map(i -> Repository.fromGithub(i, objectMapper));
    }
}
