/*
 * Licensed to the Apache Software Foundation (ASF) under one or more
 * contributor license agreements.  See the NOTICE file distributed with
 * this work for additional information regarding copyright ownership.
 * The ASF licenses this file to You under the Apache License, Version 2.0
 * (the "License"); you may not use this file except in compliance with
 * the License.  You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package org.apache.sling.scripting.jsp.taglib.init;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;

import javax.servlet.jsp.PageContext;

import org.apache.sling.commons.testing.sling.MockResource;
import org.apache.sling.commons.testing.sling.MockResourceResolver;
import org.apache.sling.scripting.jsp.taglib.MockPageContext;
import org.apache.sling.scripting.jsp.taglib.init.impl.PageContextInitializationServiceImpl;
import org.junit.Test;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Tests for the PageContextInitializationService
 */
public class TestPageContextInitializationService {

	private static final Logger log = LoggerFactory
			.getLogger(TestPageContextInitializationService.class);

	private PageContextInitializationService bindingsService = new PageContextInitializationServiceImpl();
	private MockResourceResolver resolver;

	public TestPageContextInitializationService() {
		log.info("TestResourceTypeBindingsService");
		resolver = new MockResourceResolver() {
			public String getParentResourceType(String resourceType) {
				return resourceType.replace("test", "base");
			}
		};
		resolver.setSearchPath("/apps");

		MockResource appResource = new MockResource(resolver,
				"/apps/myapp/test", null, "myapp/base");
		resolver.addResource(appResource);

		MockResource appBaseResource = new MockResource(resolver,
				"/apps/myapp/base", null);
		resolver.addResource(appBaseResource);

	}

	@Test
	public void testEscapingRules() {
		log.info("testEscapingRules");
		MockResource r = new MockResource(resolver, "/content",
				"my-component/3_rd_iteration/int");
		String className = bindingsService.getClassName(resolver,
				r.getResourceType());
		log.info("Retrieved class name: {}", className);
		assertEquals("org.apache.sling.init.my_component._3_rd_iteration.Int_",
				className);

		MockResource r2 = new MockResource(resolver, "/content",
				"my-component/3_rd_iteration/inty");
		className = bindingsService
				.getClassName(resolver, r2.getResourceType());
		log.info("Retrieved class name: {}", className);
		assertEquals("org.apache.sling.init.my_component._3_rd_iteration.Inty",
				className);

		log.info("Test successful!");
	}

	@Test
	public void testPrefixRemoval() {
		log.info("testPrefixRemoval");
		MockResource r = new MockResource(resolver, "/content",
				"/apps/my-component/3_rd_iteration/int");
		String className = bindingsService.getClassName(resolver,
				r.getResourceType());
		log.info("Retrieved class name: {}", className);
		assertEquals("org.apache.sling.init.my_component._3_rd_iteration.Int_",
				className);
		log.info("Test successful!");
	}

	@Test
	public void testBasic() {
		log.info("testResourceHeirarchy");

		MockResource content2Resource = new MockResource(resolver, "/content2",
				"myapp/base");
		resolver.addResource(content2Resource);
		PageContext context2 = new MockPageContext();
		bindingsService.initialize(context2, content2Resource);
		assertEquals("4", context2.getAttribute("A"));
		assertNull(context2.getAttribute("B"));
		assertEquals("3", context2.getAttribute("C"));
		log.info("Test successful!");
	}

	@Test
	public void testSuperTypeInheritance() {
		log.info("testResourceHeirarchy");

		MockResource contentResource = new MockResource(resolver, "/content",
				"myapp/test");
		resolver.addResource(contentResource);
		PageContext context = new MockPageContext();
		bindingsService.initialize(context, contentResource);
		assertEquals("1", context.getAttribute("A"));
		assertEquals("2", context.getAttribute("B"));
		assertEquals("3", context.getAttribute("C"));

		log.info("Test successful!");
	}
}
